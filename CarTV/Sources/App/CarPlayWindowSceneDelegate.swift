import UIKit
import WebKit
import Combine

/// A real, unrestricted WebKit browser scene for the CarPlay display when connected via
/// `UIWindowSceneSessionRoleCarPlay` (the Cafari Lite architecture).
///
/// Unlike `CPTemplateApplicationScene` (which is restricted to system-templated UI and rejects
/// arbitrary views), `UIWindowSceneSessionRoleCarPlay` hosts a real `UIWindowScene` on the head unit,
/// allowing a full `WKWebView` to render live HTML, CSS, JavaScript, and HTML5 video with direct touch input.
public final class CarPlayWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate scene:willConnectTo: role: %@", session.role.rawValue)
        guard let windowScene = scene as? UIWindowScene else {
            NSLog("DRIVEPLAY CarPlayWindowSceneDelegate ERROR: scene is not a UIWindowScene (actual: %@)", String(describing: type(of: scene)))
            return
        }

        let carWindow = UIWindow(windowScene: windowScene)
        let webVC = CarPlayWebViewController()
        carWindow.rootViewController = webVC
        carWindow.makeKeyAndVisible()
        self.window = carWindow
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate carWindow initialized, rootViewController set to CarPlayWebViewController, makeKeyAndVisible called")
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate sceneDidDisconnect")
        window = nil
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate sceneDidBecomeActive")
    }

    public func sceneWillResignActive(_ scene: UIScene) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate sceneWillResignActive")
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate sceneWillEnterForeground")
    }

    public func sceneDidEnterBackground(_ scene: UIScene) {
        NSLog("DRIVEPLAY CarPlayWindowSceneDelegate sceneDidEnterBackground")
    }
}

/// An automotive-styled, full-featured WebKit browser tailored for the CarPlay display.
/// Features address bar with Google search fallback, back/forward/reload/home navigation,
/// quick-access bookmarks, progress bar, automotive floating keyboard, and movement safety lock.
public final class CarPlayWebViewController: UIViewController,
                                             WKNavigationDelegate,
                                             WKUIDelegate,
                                             UITextFieldDelegate,
                                             CarPlayFloatingKeyboardDelegate {

    // MARK: - Properties

    private var webView: WKWebView!
    private let topContainer = UIView()
    private let toolbar = UIStackView()
    private let addressField = UITextField()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let homeButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let keyboardToggleButton = UIButton(type: .system)
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let bookmarksScrollView = UIScrollView()
    private let bookmarksStack = UIStackView()
    private let floatingKeyboard = CarPlayFloatingKeyboardView()
    private var errorBanner: UIView?
    private var drivingSafetyCover: UIView?

    private var progressObserver: NSKeyValueObservation?
    private var canGoBackObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?
    private var speedCancellable: AnyCancellable?

    private var hasRetriedCrashedPage = false
    private var replaceAddressOnNextKey = false

    private let carGreen = UIColor(red: 0.0, green: 0.816, blue: 0.400, alpha: 1.0)
    private let homeURL = URL(string: "https://www.google.com")!

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("DRIVEPLAY CarPlayWebViewController viewDidLoad")
        view.backgroundColor = .black

        configureWebView()
        configureTopBar()
        configureBookmarksBar()
        configureFloatingKeyboard()
        configureSafetyMonitoring()
        setupObservers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSendToCarNotification(_:)),
            name: Notification.Name("DrivePlaySendToCar"),
            object: nil
        )

        load(url: homeURL)
    }

    @objc private func handleSendToCarNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        load(url: url)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Respect CarPlay sidebar insets
        NSLog("DRIVEPLAY CarPlayWebViewController viewDidLayoutSubviews - bounds: %@, safeArea: %@",
              NSCoder.string(for: view.bounds),
              NSCoder.string(for: view.safeAreaInsets))
    }

    deinit {
        progressObserver?.invalidate()
        canGoBackObserver?.invalidate()
        canGoForwardObserver?.invalidate()
        speedCancellable?.cancel()
    }

    // MARK: - Setup UI

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Use modern mobile Safari User Agent for responsive website layouts
        configuration.applicationNameForUserAgent = "Mobile/15E148 Safari/604.1 DrivePlay/1.0"

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
    }

    private func configureTopBar() {
        topContainer.backgroundColor = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.98)
        topContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topContainer)

        toolbar.axis = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .center
        toolbar.distribution = .fill
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        topContainer.addSubview(toolbar)

        func styleNavButton(_ btn: UIButton, systemName: String, action: Selector) {
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            btn.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = UIColor(white: 0.22, alpha: 0.9)
            btn.layer.cornerRadius = 8
            btn.layer.masksToBounds = true
            btn.addTarget(self, action: action, for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 36),
                btn.heightAnchor.constraint(equalToConstant: 36)
            ])
        }

        styleNavButton(backButton, systemName: "chevron.left", action: #selector(handleBack))
        styleNavButton(forwardButton, systemName: "chevron.right", action: #selector(handleForward))
        styleNavButton(homeButton, systemName: "house.fill", action: #selector(handleHome))
        styleNavButton(keyboardToggleButton, systemName: "keyboard", action: #selector(toggleKeyboard))
        styleNavButton(reloadButton, systemName: "arrow.clockwise", action: #selector(handleReload))

        backButton.isEnabled = false
        forwardButton.isEnabled = false

        // Address Bar
        addressField.borderStyle = .none
        addressField.backgroundColor = UIColor(white: 0.20, alpha: 0.9)
        addressField.textColor = .white
        addressField.tintColor = carGreen
        addressField.font = .systemFont(ofSize: 14, weight: .medium)
        addressField.layer.cornerRadius = 8
        addressField.layer.masksToBounds = true
        addressField.placeholder = "Search or enter website"
        addressField.attributedPlaceholder = NSAttributedString(
            string: "Search or enter website",
            attributes: [.foregroundColor: UIColor(white: 0.6, alpha: 1.0)]
        )
        addressField.keyboardType = .URL
        addressField.returnKeyType = .go
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.delegate = self
        addressField.translatesAutoresizingMaskIntoConstraints = false

        // Left padding inside text field
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 36))
        addressField.leftView = paddingView
        addressField.leftViewMode = .always

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(homeButton)
        toolbar.addArrangedSubview(addressField)
        toolbar.addArrangedSubview(keyboardToggleButton)
        toolbar.addArrangedSubview(reloadButton)

        // Progress bar
        progressBar.progressTintColor = carGreen
        progressBar.trackTintColor = .clear
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        topContainer.addSubview(progressBar)

        NSLayoutConstraint.activate([
            topContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            topContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            toolbar.topAnchor.constraint(equalTo: topContainer.topAnchor, constant: 4),
            toolbar.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: topContainer.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 38),

            progressBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
            progressBar.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: topContainer.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    private func configureBookmarksBar() {
        bookmarksScrollView.showsHorizontalScrollIndicator = false
        bookmarksScrollView.alwaysBounceHorizontal = true
        bookmarksScrollView.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 0.95)
        bookmarksScrollView.translatesAutoresizingMaskIntoConstraints = false
        topContainer.addSubview(bookmarksScrollView)

        bookmarksStack.axis = .horizontal
        bookmarksStack.spacing = 8
        bookmarksStack.alignment = .center
        bookmarksStack.distribution = .fill
        bookmarksStack.translatesAutoresizingMaskIntoConstraints = false
        bookmarksScrollView.addSubview(bookmarksStack)

        NSLayoutConstraint.activate([
            bookmarksScrollView.topAnchor.constraint(equalTo: progressBar.bottomAnchor),
            bookmarksScrollView.leadingAnchor.constraint(equalTo: topContainer.leadingAnchor),
            bookmarksScrollView.trailingAnchor.constraint(equalTo: topContainer.trailingAnchor),
            bookmarksScrollView.bottomAnchor.constraint(equalTo: topContainer.bottomAnchor),
            bookmarksScrollView.heightAnchor.constraint(equalToConstant: 34),

            bookmarksStack.topAnchor.constraint(equalTo: bookmarksScrollView.topAnchor),
            bookmarksStack.bottomAnchor.constraint(equalTo: bookmarksScrollView.bottomAnchor),
            bookmarksStack.leadingAnchor.constraint(equalTo: bookmarksScrollView.leadingAnchor, constant: 8),
            bookmarksStack.trailingAnchor.constraint(equalTo: bookmarksScrollView.trailingAnchor, constant: -8),
            bookmarksStack.heightAnchor.constraint(equalTo: bookmarksScrollView.heightAnchor),

            // Top container bottom pinned to webview top
            webView.topAnchor.constraint(equalTo: topContainer.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let quickSites: [(title: String, url: String)] = [
            ("Google", "https://www.google.com"),
            ("YouTube", "https://m.youtube.com"),
            ("Twitch", "https://m.twitch.tv"),
            ("Wikipedia", "https://www.wikipedia.org"),
            ("Reddit", "https://m.reddit.com"),
            ("Pluto TV", "https://pluto.tv"),
            ("Hacker News", "https://news.ycombinator.com")
        ]

        for site in quickSites {
            let btn = UIButton(type: .system)
            btn.setTitle(site.title, for: .normal)
            btn.setTitleColor(UIColor(white: 0.9, alpha: 1.0), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.backgroundColor = UIColor(white: 0.22, alpha: 0.9)
            btn.layer.cornerRadius = 12
            btn.layer.masksToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.accessibilityIdentifier = site.url
            btn.addTarget(self, action: #selector(handleBookmarkTap(_:)), for: .touchUpInside)
            bookmarksStack.addArrangedSubview(btn)
        }
    }

    private func configureFloatingKeyboard() {
        floatingKeyboard.delegate = self
        floatingKeyboard.isHidden = true
        floatingKeyboard.alpha = 0.0
        floatingKeyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingKeyboard)

        NSLayoutConstraint.activate([
            floatingKeyboard.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            floatingKeyboard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            floatingKeyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            floatingKeyboard.heightAnchor.constraint(equalToConstant: 220)
        ])
    }

    private func configureSafetyMonitoring() {
        // Monitor speed for automotive video/browsing safety
        speedCancellable = SatelliteHUDService.shared.$currentSpeedKmh
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speed in
                guard let self = self else { return }
                // > 11 km/h (~3.0 m/s) is vehicle in motion
                if speed > 11.0 {
                    self.showSafetyCover()
                } else {
                    self.hideSafetyCover()
                }
            }
    }

    private func setupObservers() {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.progressBar.progress = Float(webView.estimatedProgress)
                self.progressBar.isHidden = webView.estimatedProgress >= 1.0
            }
        }

        canGoBackObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.backButton.isEnabled = webView.canGoBack
                self.backButton.tintColor = webView.canGoBack ? .white : UIColor(white: 0.4, alpha: 1.0)
            }
        }

        canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.forwardButton.isEnabled = webView.canGoForward
                self.forwardButton.tintColor = webView.canGoForward ? .white : UIColor(white: 0.4, alpha: 1.0)
            }
        }
    }

    // MARK: - Navigation Actions

    public func load(url: URL) {
        NSLog("DRIVEPLAY CarPlayWebViewController loading URL: %@", url.absoluteString)
        hideError()
        webView.load(URLRequest(url: url))
    }

    private func navigate(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            if let direct = URL(string: trimmed) {
                targetURL = direct
            } else {
                targetURL = searchURL(for: trimmed)
            }
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            if let formatted = URL(string: "https://" + trimmed) {
                targetURL = formatted
            } else {
                targetURL = searchURL(for: trimmed)
            }
        } else {
            targetURL = searchURL(for: trimmed)
        }

        load(url: targetURL)
    }

    private func searchURL(for query: String) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url ?? homeURL
    }

    @objc private func handleBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func handleForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @objc private func handleHome() {
        load(url: homeURL)
    }

    @objc private func handleReload() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    @objc private func handleBookmarkTap(_ sender: UIButton) {
        guard let urlString = sender.accessibilityIdentifier, let url = URL(string: urlString) else { return }
        load(url: url)
    }

    @objc private func toggleKeyboard() {
        if floatingKeyboard.isHidden {
            showKeyboard()
        } else {
            hideKeyboard()
        }
    }

    private func showKeyboard() {
        replaceAddressOnNextKey = true
        floatingKeyboard.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.floatingKeyboard.alpha = 1.0
        }
    }

    private func hideKeyboard() {
        UIView.animate(withDuration: 0.25, animations: {
            self.floatingKeyboard.alpha = 0.0
        }) { _ in
            self.floatingKeyboard.isHidden = true
        }
    }

    // MARK: - Safety Cover

    private func showSafetyCover() {
        // Pause any HTML5 video tags currently playing
        webView.evaluateJavaScript(
            "document.querySelectorAll('video').forEach(v => v.pause())", completionHandler: nil)

        guard drivingSafetyCover == nil else { return }

        let cover = UIView()
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        cover.translatesAutoresizingMaskIntoConstraints = false

        let lockIcon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        lockIcon.tintColor = carGreen
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(lockIcon)

        let label = UILabel()
        label.text = "Browsing and Video Paused\nWhile Vehicle is in Motion"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(label)

        let subLabel = UILabel()
        subLabel.text = "Playback will automatically resume when the vehicle is parked."
        subLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
        subLabel.textAlignment = .center
        subLabel.numberOfLines = 0
        subLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(subLabel)

        view.addSubview(cover)

        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: view.topAnchor),
            cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            lockIcon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            lockIcon.centerYAnchor.constraint(equalTo: cover.centerYAnchor, constant: -40),
            lockIcon.widthAnchor.constraint(equalToConstant: 44),
            lockIcon.heightAnchor.constraint(equalToConstant: 44),

            label.topAnchor.constraint(equalTo: lockIcon.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -24),

            subLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            subLabel.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            subLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 24),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -24)
        ])

        drivingSafetyCover = cover
        NSLog("DRIVEPLAY CarPlayWebViewController safety cover presented (vehicle in motion)")
    }

    private func hideSafetyCover() {
        guard let cover = drivingSafetyCover else { return }
        cover.removeFromSuperview()
        drivingSafetyCover = nil
        NSLog("DRIVEPLAY CarPlayWebViewController safety cover dismissed (vehicle stationary)")
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        hideError()

        let banner = UIView()
        banner.backgroundColor = UIColor(red: 0.25, green: 0.10, blue: 0.10, alpha: 0.95)
        banner.layer.cornerRadius = 10
        banner.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.text = message
        lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.numberOfLines = 2
        lbl.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(lbl)

        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.setTitleColor(.white, for: .normal)
        retry.backgroundColor = carGreen
        retry.layer.cornerRadius = 6
        retry.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        retry.addTarget(self, action: #selector(handleReload), for: .touchUpInside)
        retry.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(retry)

        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: topContainer.bottomAnchor, constant: 10),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            lbl.topAnchor.constraint(equalTo: banner.topAnchor, constant: 8),
            lbl.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -8),
            lbl.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),

            retry.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 12),
            retry.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            retry.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            retry.widthAnchor.constraint(equalToConstant: 60),
            retry.heightAnchor.constraint(equalToConstant: 28)
        ])

        errorBanner = banner
    }

    private func hideError() {
        errorBanner?.removeFromSuperview()
        errorBanner = nil
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === addressField {
            showKeyboard()
            return false // Floating keyboard edits this field
        }
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === addressField {
            navigate(to: textField.text ?? "")
            hideKeyboard()
        }
        return true
    }

    // MARK: - CarPlayFloatingKeyboardDelegate

    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didEnterText text: String) {
        if replaceAddressOnNextKey {
            addressField.text = text
            replaceAddressOnNextKey = false
        } else {
            addressField.text = (addressField.text ?? "") + text
        }
    }

    public func floatingKeyboardDidTapDelete(_ keyboard: CarPlayFloatingKeyboardView) {
        if replaceAddressOnNextKey {
            addressField.text = ""
            replaceAddressOnNextKey = false
            return
        }
        var current = addressField.text ?? ""
        if !current.isEmpty {
            current.removeLast()
            addressField.text = current
        }
    }

    public func floatingKeyboardDidTapClear(_ keyboard: CarPlayFloatingKeyboardView) {
        addressField.text = ""
        replaceAddressOnNextKey = false
    }

    public func floatingKeyboardDidTapGo(_ keyboard: CarPlayFloatingKeyboardView) {
        navigate(to: addressField.text ?? "")
        hideKeyboard()
    }

    public func floatingKeyboardDidTapDismiss(_ keyboard: CarPlayFloatingKeyboardView) {
        hideKeyboard()
    }

    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didSelectQuickItem text: String) {
        if ["youtube.com", "google.com", "twitch.tv", "wikipedia.org", "reddit.com"].contains(text) {
            navigate(to: text)
            hideKeyboard()
        } else {
            if replaceAddressOnNextKey {
                addressField.text = text
                replaceAddressOnNextKey = false
            } else {
                addressField.text = (addressField.text ?? "") + text
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NSLog("DRIVEPLAY CarPlayWebViewController didStartProvisionalNavigation: %@", webView.url?.absoluteString ?? "-")
        hideError()
        reloadButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        NSLog("DRIVEPLAY CarPlayWebViewController didCommit: %@", webView.url?.absoluteString ?? "-")
        addressField.text = webView.url?.absoluteString
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("DRIVEPLAY CarPlayWebViewController didFinish: %@ (bounds: %@)",
              webView.url?.absoluteString ?? "-",
              NSCoder.string(for: webView.bounds))
        hasRetriedCrashedPage = false
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        addressField.text = webView.url?.absoluteString
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("DRIVEPLAY CarPlayWebViewController didFail: %@", error.localizedDescription)
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        if (error as NSError).code != NSURLErrorCancelled {
            showError(message: error.localizedDescription)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("DRIVEPLAY CarPlayWebViewController didFailProvisionalNavigation: %@", error.localizedDescription)
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        if (error as NSError).code != NSURLErrorCancelled {
            showError(message: error.localizedDescription)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("DRIVEPLAY CarPlayWebViewController webContentProcessDidTerminate")
        if !hasRetriedCrashedPage {
            hasRetriedCrashedPage = true
            webView.reload()
        } else {
            showError(message: "Web process terminated. Please retry.")
        }
    }

    // MARK: - WKUIDelegate

    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open target=_blank links inside the same webView
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
