import UIKit
import WebKit

/// A genuine WebKit browser for an interactive UIWindowScene (iPhone or
/// a supported interactive external display). This is NOT a CarPlay template.
/// Requires the existing CarPlayFloatingKeyboardView.swift in the same target.
@MainActor
final class DrivePlayRealBrowserViewController: UIViewController,
                                               WKNavigationDelegate,
                                               WKUIDelegate,
                                               UITextFieldDelegate,
                                               CarPlayFloatingKeyboardDelegate {
    var onClose: (() -> Void)?

    private let initialURL: URL?
    private let webView: WKWebView
    private let addressField = UITextField()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let homeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let toolbar = UIView()
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let errorLabel = UILabel()
    private let floatingKeyboard = CarPlayFloatingKeyboardView()
    private var progressObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var hasRetriedCrashedPage = false
    // First key replaces the current URL instead of appending to it.
    private var replaceAddressOnNextKey = false

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Normal WebKit policies still apply to websites and protected media.
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        configureWebView()
        observeWebView()
        open(url: initialURL ?? URL(string: "https://www.google.com")!)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Avoid leaving a visible keyboard overlay after closing.
        floatingKeyboard.isHidden = true
    }

    private func configureUI() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .secondarySystemBackground
        view.addSubview(toolbar)

        func setUp(_ button: UIButton, symbol: String, label: String, action: Selector) {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = label
            button.tintColor = .label
            button.addTarget(self, action: action, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 38).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        setUp(closeButton, symbol: "xmark", label: "Close", action: #selector(closeTapped))
        setUp(backButton, symbol: "chevron.left", label: "Back", action: #selector(backTapped))
        setUp(forwardButton, symbol: "chevron.right", label: "Forward", action: #selector(forwardTapped))
        setUp(homeButton, symbol: "house", label: "Home", action: #selector(homeTapped))
        setUp(reloadButton, symbol: "arrow.clockwise", label: "Reload", action: #selector(reloadTapped))

        addressField.borderStyle = .roundedRect
        addressField.backgroundColor = .tertiarySystemBackground
        addressField.placeholder = "Address or search"
        addressField.textContentType = .URL
        addressField.keyboardType = .URL
        addressField.returnKeyType = .go
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.delegate = self
        addressField.accessibilityIdentifier = "driveplay.browser.address"
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controls = UIStackView(arrangedSubviews: [
            closeButton, backButton, forwardButton, homeButton, addressField, reloadButton
        ])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 4
        toolbar.addSubview(controls)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.progressTintColor = .systemGreen
        progressBar.isHidden = true
        view.addSubview(progressBar)

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.92)
        errorLabel.textColor = .white
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.numberOfLines = 2
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
        view.addSubview(errorLabel)

        floatingKeyboard.translatesAutoresizingMaskIntoConstraints = false
        floatingKeyboard.delegate = self
        floatingKeyboard.isHidden = true
        view.addSubview(floatingKeyboard)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 54),

            controls.leadingAnchor.constraint(equalTo: toolbar.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: toolbar.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            controls.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 38),

            progressBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),

            floatingKeyboard.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            floatingKeyboard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            floatingKeyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            floatingKeyboard.heightAnchor.constraint(equalToConstant: 220)
        ])
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.backgroundColor = .systemBackground
    }

    private func observeWebView() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new, .initial]) { [weak self] view, _ in
            let progress = Float(view.estimatedProgress)
            let isLoading = view.isLoading
            DispatchQueue.main.async { [weak self] in
                self?.progressBar.progress = progress
                self?.progressBar.isHidden = !isLoading
            }
        }
        backObservation = webView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] view, _ in
            let enabled = view.canGoBack
            DispatchQueue.main.async { [weak self] in self?.backButton.isEnabled = enabled }
        }
        forwardObservation = webView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] view, _ in
            let enabled = view.canGoForward
            DispatchQueue.main.async { [weak self] in self?.forwardButton.isEnabled = enabled }
        }
    }

    /// Call this to navigate an already-presented browser.
    func open(url: URL) {
        guard isViewLoaded else { return }
        guard let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil else {
            showError("Enter a valid website address.")
            return
        }
        hideKeyboard()
        errorLabel.isHidden = true
        addressField.text = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func navigate(_ input: String) {
        guard let url = Self.destination(for: input) else {
            showError("Enter a website address or search text.")
            return
        }
        open(url: url)
    }

    /// Uses URLComponents so search terms are encoded correctly.
    static func destination(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let components = URLComponents(string: text),
           let scheme = components.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = components.host, !host.isEmpty {
            return components.url
        }
        // A bare hostname can include a port, path, and query parameters.
        if !text.contains(where: { $0.isWhitespace }), text.contains("."),
           let url = URL(string: "https://" + text), url.host != nil {
            return url
        }
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }

    private func showKeyboard() {
        replaceAddressOnNextKey = true
        floatingKeyboard.isHidden = false
        view.bringSubviewToFront(floatingKeyboard)
    }

    private func hideKeyboard() {
        replaceAddressOnNextKey = false
        floatingKeyboard.isHidden = true
    }

    private func showError(_ message: String) {
        errorLabel.text = "  " + message + "  "
        errorLabel.isHidden = false
    }

    @objc private func closeTapped() {
        webView.stopLoading()
        hideKeyboard()
        if let onClose { onClose() }
        else { dismiss(animated: true) }
    }
    @objc private func backTapped() {
        hideKeyboard()
        if webView.canGoBack { webView.goBack() }
    }
    @objc private func forwardTapped() {
        hideKeyboard()
        if webView.canGoForward { webView.goForward() }
    }
    @objc private func reloadTapped() {
        hideKeyboard()
        if webView.isLoading { webView.stopLoading() }
        else { webView.reload() }
    }
    @objc private func homeTapped() {
        open(url: URL(string: "https://www.google.com")!)
    }

    // MARK: - Address bar and existing automotive keyboard

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === addressField {
            showKeyboard()
            return false // The car's own on-screen keyboard edits this field.
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === addressField { navigate(textField.text ?? "") }
        return true
    }

    func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didEnterText text: String) {
        if replaceAddressOnNextKey {
            addressField.text = text
            replaceAddressOnNextKey = false
        } else {
            addressField.text = (addressField.text ?? "") + text
        }
    }
    func floatingKeyboardDidTapDelete(_ keyboard: CarPlayFloatingKeyboardView) {
        if replaceAddressOnNextKey {
            addressField.text = ""
            replaceAddressOnNextKey = false
            return
        }
        var value = addressField.text ?? ""
        if !value.isEmpty { value.removeLast() }
        addressField.text = value
    }
    func floatingKeyboardDidTapClear(_ keyboard: CarPlayFloatingKeyboardView) {
        addressField.text = ""
        replaceAddressOnNextKey = false
    }
    func floatingKeyboardDidTapGo(_ keyboard: CarPlayFloatingKeyboardView) {
        navigate(addressField.text ?? "")
    }
    func floatingKeyboardDidTapDismiss(_ keyboard: CarPlayFloatingKeyboardView) {
        hideKeyboard()
    }
    func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didSelectQuickItem text: String) {
        if ["youtube.com", "google.com", "twitch.tv"].contains(text) {
            navigate(text)
        } else {
            if replaceAddressOnNextKey {
                addressField.text = text
                replaceAddressOnNextKey = false
            } else {
                addressField.text = (addressField.text ?? "") + text
            }
        }
    }

    // MARK: - Actual webpage navigation and rendering

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorLabel.isHidden = true
        progressBar.isHidden = false
        progressBar.progress = 0.05
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        addressField.text = webView.url?.absoluteString
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasRetriedCrashedPage = false
        progressBar.isHidden = true
        addressField.text = webView.url?.absoluteString
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        displayNavigationError(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        displayNavigationError(error)
    }
    private func displayNavigationError(_ error: Error) {
        progressBar.isHidden = true
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError(error.localizedDescription)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if hasRetriedCrashedPage { showError("Page crashed twice. Try another website."); return }
        hasRetriedCrashedPage = true
        webView.reload()
    }
    // Open target=_blank links in the same browser window.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Additive integration for the repository's existing external-display controller.
/// Does not touch CarPlaySceneDelegate or modify iPhone tab selection.
extension InCarAutomotiveController {
    func presentRealWebBrowser(url: URL? = nil) {
        guard isInteractive else {
            let alert = UIAlertController(
                title: "Interactive browser unavailable",
                message: "This external display does not report interactive input support.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        if let existing = presentedViewController as? DrivePlayRealBrowserViewController {
            if let url { existing.open(url: url) }
            return
        }
        let browser = DrivePlayRealBrowserViewController(initialURL: url)
        browser.modalPresentationStyle = .fullScreen
        present(browser, animated: true)
    }
}
