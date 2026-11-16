// DrivePlay experimental CarPlay window browser
// Original replacement implementation for DrivePlay-iOS.
// Architecture inspired by rPlayAI/cafari-lite (MIT), with attribution in the accompanying README.
// IMPORTANT: UIWindowSceneSessionRoleCarPlay is not a documented public browser API.
// The system may never create this scene; CPTemplateApplicationScene remains the supported fallback.

import UIKit
import WebKit
import CoreLocation

private let drivePlayWindowRole = UISceneSession.Role(rawValue: "UIWindowSceneSessionRoleCarPlay")

public final class CarPlayWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    public func scene(_ scene: UIScene,
                      willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
        NSLog("DRIVEPLAY-WEB scene connected role=%@ type=%@", session.role.rawValue,
              String(describing: type(of: scene)))
        guard session.role == drivePlayWindowRole || session.role.rawValue == "UIWindowSceneSessionRoleCarPlay",
              let windowScene = scene as? UIWindowScene else {
            NSLog("DRIVEPLAY-WEB cannot attach browser: this is not the experimental CarPlay window")
            return
        }
        let carWindow = UIWindow(windowScene: windowScene)
        carWindow.rootViewController = CarPlayWebViewController()
        carWindow.makeKeyAndVisible()
        self.window = carWindow
        NSLog("DRIVEPLAY-WEB WKWebView window ready bounds=%@", NSCoder.string(for: carWindow.bounds))
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        NSLog("DRIVEPLAY-WEB scene disconnected")
        (window?.rootViewController as? CarPlayWebViewController)?.shutDown()
        window = nil
    }
}

/// A Safari-style WebKit browser for the EXPERIMENTAL car UIWindowScene.
/// It is not Apple's Safari app and does not run within CPTemplateApplicationScene.
public final class CarPlayWebViewController: UIViewController,
                                            WKNavigationDelegate,
                                            WKUIDelegate,
                                            UITextFieldDelegate,
                                            CarPlayFloatingKeyboardDelegate,
                                            WKScriptMessageHandler {

    private enum InputTarget { case address, webpage }

    private final class BrowserTab {
        let webView: WKWebView
        init(webView: WKWebView) { self.webView = webView }
    }

    // WKUserContentController strongly retains handlers. This weak proxy prevents
    // a browser -> WKWebView -> script handler -> browser retain cycle.
    private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            target?.userContentController(userContentController, didReceive: message)
        }
    }

    private let homeURL = URL(string: "https://example.com")!
    private let accent = UIColor(red: 0.0, green: 0.816, blue: 0.400, alpha: 1)
    private let controls = UIStackView()
    public let address = UITextField()
    public let progress = UIProgressView(progressViewStyle: .bar)
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private let reload = UIButton(type: .system)
    private let home = UIButton(type: .system)
    private let tabsButton = UIButton(type: .system)
    private let keyboardButton = UIButton(type: .system)
    public let pageHost = UIView()
    public let status = UILabel()
    public let keyboard = CarPlayFloatingKeyboardView()
    public let lockOverlay = UIView()
    public let lockMessage = UILabel()
    public let parkedButton = UIButton(type: .system)

    private var tabs: [BrowserTab] = []
    private var activeTabIndex = 0
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var inputTarget: InputTarget = .address
    private var replaceAddressOnNextKey = false
    private var keyboardVisible = false
    private var nativePixelLayout = false
    private var webCrashRetries = Set<ObjectIdentifier>()
    let gate = CarBrowserParkingGate()

    public var currentWebView: WKWebView {
        if tabs.isEmpty {
            let fallback = makeWebView()
            pageHost.addSubview(fallback)
            tabs.append(BrowserTab(webView: fallback))
            activeTabIndex = 0
        }
        return tabs[activeTabIndex].webView
    }

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureChrome()
        configureKeyboard()
        configureGate()
        createTab(url: homeURL)
        gate.start()
        NSLog("DRIVEPLAY-WEB browser loaded; car-only WebKit instance")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutWebView()
        let kbHeight = keyboardHeight()
        keyboard.frame = CGRect(x: view.safeAreaInsets.left,
                                y: view.bounds.height - view.safeAreaInsets.bottom - kbHeight,
                                width: max(0, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right),
                                height: kbHeight)
    }

    public func shutDown() {
        gate.stop()
        progressObservation = nil
        urlObservation = nil
        backObservation = nil
        forwardObservation = nil
        for tab in tabs {
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
            tab.webView.configuration.userContentController.removeScriptMessageHandler(forName: "driveplayFocus")
            tab.webView.removeFromSuperview()
        }
        tabs.removeAll()
        NSLog("DRIVEPLAY-WEB browser shut down")
    }

    deinit { gate.stop() }

    // MARK: - UI

    private func configureChrome() {
        pageHost.backgroundColor = .white
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageHost)

        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 5
        controls.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 0.96)
        controls.isLayoutMarginsRelativeArrangement = true
        controls.layoutMargins = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        [back, forward, home, reload, keyboardButton, tabsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        styleButton(back, icon: "chevron.backward", action: #selector(goBack))
        styleButton(forward, icon: "chevron.forward", action: #selector(goForward))
        styleButton(home, icon: "house.fill", action: #selector(goHome))
        styleButton(reload, icon: "arrow.clockwise", action: #selector(reloadPage))
        styleButton(keyboardButton, icon: "keyboard", action: #selector(editAddress))
        styleButton(tabsButton, icon: "square.on.square", action: #selector(showTabs))
        back.isEnabled = false
        forward.isEnabled = false

        address.textColor = .white
        address.backgroundColor = UIColor(white: 0.24, alpha: 1)
        address.font = .systemFont(ofSize: 13)
        address.layer.cornerRadius = 7
        address.clipsToBounds = true
        address.autocapitalizationType = .none
        address.autocorrectionType = .no
        address.keyboardType = .URL
        address.returnKeyType = .go
        address.placeholder = "Address or search"
        address.attributedPlaceholder = NSAttributedString(string: "Address or search",
            attributes: [.foregroundColor: UIColor(white: 0.68, alpha: 1)])
        address.textAlignment = .center
        address.delegate = self
        address.accessibilityIdentifier = "driveplay.car.address"
        address.translatesAutoresizingMaskIntoConstraints = false
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        controls.addArrangedSubview(back)
        controls.addArrangedSubview(forward)
        controls.addArrangedSubview(home)
        controls.addArrangedSubview(address)
        controls.addArrangedSubview(keyboardButton)
        controls.addArrangedSubview(reload)
        controls.addArrangedSubview(tabsButton)

        progress.progressTintColor = accent
        progress.trackTintColor = .clear
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)

        status.textColor = .white
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.numberOfLines = 2
        status.textAlignment = .center
        status.backgroundColor = UIColor(white: 0.05, alpha: 0.90)
        status.layer.cornerRadius = 6
        status.clipsToBounds = true
        status.isHidden = true
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)

        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            controls.heightAnchor.constraint(equalToConstant: 44),
            address.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            progress.topAnchor.constraint(equalTo: controls.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            pageHost.topAnchor.constraint(equalTo: progress.bottomAnchor),
            pageHost.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            pageHost.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 5),
            status.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9),
            status.heightAnchor.constraint(greaterThanOrEqualToConstant: 25)
        ])
    }

    private func styleButton(_ button: UIButton, icon: String, action: Selector) {
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(white: 0.18, alpha: 0.94)
        button.layer.cornerRadius = 7
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func keyboardHeight() -> CGFloat {
        min(220, max(145, view.bounds.height * 0.57))
    }

    private func configureKeyboard() {
        keyboard.delegate = self
        keyboard.isHidden = true
        keyboard.alpha = 0
        view.addSubview(keyboard)
    }

    private func setKeyboard(visible: Bool, target: InputTarget? = nil) {
        guard !gate.isLocked else { return }
        if let target { inputTarget = target }
        keyboardVisible = visible
        keyboard.isHidden = !visible
        keyboard.alpha = visible ? 1 : 0
        view.bringSubviewToFront(keyboard)
        // Keep webpage fields above the keyboard where possible.
        let inset = visible ? keyboardHeight() : 0
        if !tabs.isEmpty {
            currentWebView.scrollView.contentInset.bottom = inset
            currentWebView.scrollView.scrollIndicatorInsets.bottom = inset
        }
        view.setNeedsLayout()
    }

    private func configureGate() {
        gate.onChange = { [weak self] locked, reason, mayConfirm in
            self?.updateGate(locked: locked, reason: reason, mayConfirm: mayConfirm)
        }
        lockOverlay.backgroundColor = .black
        lockOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lockOverlay)
        lockMessage.textColor = .white
        lockMessage.textAlignment = .center
        lockMessage.numberOfLines = 0
        lockMessage.font = .systemFont(ofSize: 17, weight: .semibold)
        lockMessage.translatesAutoresizingMaskIntoConstraints = false
        lockOverlay.addSubview(lockMessage)
        parkedButton.setTitle("Confirm parked", for: .normal)
        parkedButton.setTitleColor(.black, for: .normal)
        parkedButton.backgroundColor = accent
        parkedButton.layer.cornerRadius = 9
        parkedButton.addTarget(self, action: #selector(confirmParked), for: .touchUpInside)
        parkedButton.translatesAutoresizingMaskIntoConstraints = false
        lockOverlay.addSubview(parkedButton)
        NSLayoutConstraint.activate([
            lockOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lockOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lockOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            lockOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            lockMessage.centerXAnchor.constraint(equalTo: lockOverlay.centerXAnchor),
            lockMessage.centerYAnchor.constraint(equalTo: lockOverlay.centerYAnchor, constant: -25),
            lockMessage.leadingAnchor.constraint(equalTo: lockOverlay.leadingAnchor, constant: 20),
            lockMessage.trailingAnchor.constraint(equalTo: lockOverlay.trailingAnchor, constant: -20),
            parkedButton.topAnchor.constraint(equalTo: lockMessage.bottomAnchor, constant: 12),
            parkedButton.centerXAnchor.constraint(equalTo: lockOverlay.centerXAnchor),
            parkedButton.widthAnchor.constraint(equalToConstant: 160),
            parkedButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        updateGate(locked: true,
                   reason: "Car browser is locked until parked status is confirmed.",
                   mayConfirm: true)
    }

    private func updateGate(locked: Bool, reason: String, mayConfirm: Bool) {
        lockOverlay.isHidden = !locked
        lockMessage.text = reason
        parkedButton.isHidden = !mayConfirm
        if locked {
            setKeyboardForceHidden()
            if !tabs.isEmpty {
                currentWebView.evaluateJavaScript(
                    "document.querySelectorAll('video,audio').forEach(x=>x.pause())",
                    completionHandler: nil)
            }
        }
        view.bringSubviewToFront(lockOverlay)
    }

    private func setKeyboardForceHidden() {
        keyboardVisible = false
        keyboard.alpha = 0
        keyboard.isHidden = true
    }

    @objc private func confirmParked() { gate.confirmParked() }

    // MARK: - New independent WKWebView for every tab

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        AdBlockerEngine.shared.apply(to: config)

        let script = WKUserScript(source: Self.focusTrackingScript,
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(WeakMessageHandler(self), name: "driveplayFocus")
        let result = WKWebView(frame: .zero, configuration: config)
        result.navigationDelegate = self
        result.uiDelegate = self
        result.backgroundColor = .white
        result.allowsBackForwardNavigationGestures = true
        result.scrollView.contentInsetAdjustmentBehavior = .never
        return result
    }

    private func createTab(url: URL) {
        guard tabs.count < 8 else { showStatus("Maximum 8 tabs"); return }
        if !tabs.isEmpty { currentWebView.isHidden = true }
        let web = makeWebView()
        pageHost.addSubview(web)
        tabs.append(BrowserTab(webView: web))
        activeTabIndex = tabs.count - 1
        observeCurrentTab()
        setKeyboard(visible: false)
        layoutWebView()
        web.load(URLRequest(url: url))
        showStatus("Loading \(url.host ?? url.absoluteString)")
    }

    private func observeCurrentTab() {
        progressObservation = nil
        urlObservation = nil
        backObservation = nil
        forwardObservation = nil
        let web = currentWebView
        progressObservation = web.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateToolbar() }
        }
        urlObservation = web.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateToolbar() }
        }
        backObservation = web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateToolbar() }
        }
        forwardObservation = web.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateToolbar() }
        }
        updateToolbar()
    }

    private func switchTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        setKeyboard(visible: false)
        currentWebView.isHidden = true
        activeTabIndex = index
        currentWebView.isHidden = false
        observeCurrentTab()
        layoutWebView()
    }

    private func closeCurrentTab() {
        if tabs.count <= 1 {
            currentWebView.load(URLRequest(url: homeURL))
            return
        }
        let tab = tabs.remove(at: activeTabIndex)
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        tab.webView.configuration.userContentController.removeScriptMessageHandler(forName: "driveplayFocus")
        tab.webView.removeFromSuperview()
        activeTabIndex = min(activeTabIndex, tabs.count - 1)
        switchTab(activeTabIndex)
    }

    private func updateToolbar() {
        guard !tabs.isEmpty else { return }
        let web = currentWebView
        back.isEnabled = web.canGoBack
        forward.isEnabled = web.canGoForward
        progress.progress = Float(web.estimatedProgress)
        progress.isHidden = !web.isLoading
        reload.setImage(UIImage(systemName: web.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        // Do not overwrite a partially typed address while the keyboard is open.
        if !keyboardVisible || inputTarget != .address {
            address.text = web.url?.absoluteString ?? ""
        }
    }

    private func layoutWebView() {
        guard !tabs.isEmpty else { return }
        let web = currentWebView
        let bounds = pageHost.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        web.transform = .identity
        if nativePixelLayout, let screen = view.window?.windowScene?.screen {
            let pixels = screen.nativeBounds.size
            let viewport = CGSize(width: max(pixels.width, pixels.height),
                                  height: min(pixels.width, pixels.height))
            if viewport.width > 0 && viewport.height > 0 {
                web.frame = CGRect(origin: .zero, size: viewport)
                web.transform = CGAffineTransform(scaleX: bounds.width / viewport.width,
                                                  y: bounds.height / viewport.height)
                web.center = CGPoint(x: bounds.midX, y: bounds.midY)
                return
            }
        }
        web.frame = bounds
    }

    // MARK: - Navigation

    @objc private func goBack() { if currentWebView.canGoBack { currentWebView.goBack() } }
    @objc private func goForward() { if currentWebView.canGoForward { currentWebView.goForward() } }
    @objc private func goHome() { loadText(homeURL.absoluteString) }
    @objc private func reloadPage() {
        if currentWebView.isLoading { currentWebView.stopLoading() }
        else { currentWebView.reload() }
    }
    @objc private func editAddress() {
        inputTarget = .address
        replaceAddressOnNextKey = true
        setKeyboard(visible: true, target: .address)
    }

    private func loadText(_ text: String) {
        guard let url = Self.destination(for: text) else {
            showStatus("Enter a valid website or search")
            return
        }
        setKeyboard(visible: false)
        currentWebView.load(URLRequest(url: url))
    }

    // This is deliberately not a scheme-launcher: javascript:, data:, and
    // custom URL schemes cannot run from the car's address field.
    static func destination(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            if let url = URL(string: text),
               let scheme = url.scheme?.lowercased(),
               ["https", "http"].contains(scheme),
               let host = url.host, !host.isEmpty { return url }
        } else if !text.contains(where: { $0.isWhitespace }),
                  !text.contains("://"),
                  !text.contains("@"),
                  (text.contains(".") || lower == "localhost"),
                  let url = URL(string: "https://" + text),
                  let host = url.host, !host.isEmpty { return url }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }

    @objc private func showTabs() {
        setKeyboard(visible: false)
        let alert = UIAlertController(title: "Browser tabs", message: "Choose a page", preferredStyle: .actionSheet)
        for (index, tab) in tabs.enumerated() {
            let name = tab.webView.title ?? tab.webView.url?.host ?? "New tab"
            alert.addAction(UIAlertAction(title: "\(index == activeTabIndex ? "✓ " : "")\(name)", style: .default) { [weak self] _ in
                self?.switchTab(index)
            })
        }
        if tabs.count < 8 {
            alert.addAction(UIAlertAction(title: "New tab", style: .default) { [weak self] _ in
                self?.createTab(url: self?.homeURL ?? URL(string: "https://example.com")!)
            })
        }
        alert.addAction(UIAlertAction(title: "Close current tab", style: .destructive) { [weak self] _ in
            self?.closeCurrentTab()
        })
        alert.addAction(UIAlertAction(title: "Bookmark this page", style: .default) { [weak self] _ in
            self?.addBookmark()
        })
        alert.addAction(UIAlertAction(title: "Open bookmark", style: .default) { [weak self] _ in
            self?.showBookmarks()
        })
        alert.addAction(UIAlertAction(title: "History", style: .default) { [weak self] _ in
            self?.showHistory()
        })
        alert.addAction(UIAlertAction(title: nativePixelLayout ? "Use readable layout" : "Use native pixel layout", style: .default) { [weak self] _ in
            guard let self else { return }
            self.nativePixelLayout.toggle()
            self.layoutWebView()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tabsButton
        alert.popoverPresentationController?.sourceRect = tabsButton.bounds
        present(alert, animated: true)
    }

    // Stored locally in DrivePlay's app container; active car tabs remain independent
    // of the phone tab selection and do not invoke BrowserTabManager.shared.
    private static let bookmarkKey = "driveplay.car.web.bookmarks.v1"

    private func addBookmark() {
        guard let url = currentWebView.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        var saved = UserDefaults.standard.stringArray(forKey: Self.bookmarkKey) ?? []
        saved.removeAll(where: { $0 == url.absoluteString })
        saved.insert(url.absoluteString, at: 0)
        UserDefaults.standard.set(Array(saved.prefix(50)), forKey: Self.bookmarkKey)
        showStatus("Bookmark saved")
    }

    private func showBookmarks() {
        let urls = UserDefaults.standard.stringArray(forKey: Self.bookmarkKey) ?? []
        let menu = UIAlertController(title: "Bookmarks", message: urls.isEmpty ? "No bookmarks saved yet" : nil,
                                     preferredStyle: .actionSheet)
        for saved in urls.prefix(20) {
            guard let url = Self.destination(for: saved) else { continue }
            menu.addAction(UIAlertAction(title: url.host ?? saved, style: .default) { [weak self] _ in
                self?.loadText(saved)
            })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.sourceView = tabsButton
        menu.popoverPresentationController?.sourceRect = tabsButton.bounds
        present(menu, animated: true)
    }

    private func showHistory() {
        let list = currentWebView.backForwardList
        let entries = Array(list.backList.suffix(12).reversed()) + [list.currentItem].compactMap { $0 }
        let menu = UIAlertController(title: "This tab's history", message: entries.isEmpty ? "No history" : nil,
                                     preferredStyle: .actionSheet)
        for item in entries {
            menu.addAction(UIAlertAction(title: item.title ?? item.url.host ?? item.url.absoluteString,
                                         style: .default) { [weak self] _ in
                guard let self else { return }
                self.currentWebView.go(to: item)
            })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.sourceView = tabsButton
        menu.popoverPresentationController?.sourceRect = tabsButton.bounds
        present(menu, animated: true)
    }

    private func showStatus(_ message: String) {
        status.text = "  " + message + "  "
        status.isHidden = false
    }

    private func clearStatus() {
        status.isHidden = true
    }

    // MARK: - UITextFieldDelegate and floating keyboard

    public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === address { editAddress(); return false }
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === address else { return true }
        loadText(address.text ?? "")
        return true
    }

    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didEnterText text: String) {
        insertKeyboardText(text)
    }

    public func floatingKeyboardDidTapDelete(_ keyboard: CarPlayFloatingKeyboardView) {
        if inputTarget == .webpage { editWebInput(operation: "backspace", text: ""); return }
        if replaceAddressOnNextKey {
            address.text = ""
            replaceAddressOnNextKey = false
        } else {
            var value = address.text ?? ""
            if !value.isEmpty { value.removeLast() }
            address.text = value
        }
    }

    public func floatingKeyboardDidTapClear(_ keyboard: CarPlayFloatingKeyboardView) {
        if inputTarget == .webpage { editWebInput(operation: "clear", text: ""); return }
        address.text = ""
        replaceAddressOnNextKey = false
    }

    public func floatingKeyboardDidTapGo(_ keyboard: CarPlayFloatingKeyboardView) {
        if inputTarget == .webpage {
            editWebInput(operation: "submit", text: "")
            setKeyboard(visible: false)
        } else {
            loadText(address.text ?? "")
        }
    }

    public func floatingKeyboardDidTapDismiss(_ keyboard: CarPlayFloatingKeyboardView) {
        setKeyboard(visible: false)
    }

    public func floatingKeyboard(_ keyboard: CarPlayFloatingKeyboardView, didSelectQuickItem text: String) {
        if inputTarget == .webpage { editWebInput(operation: "insert", text: text); return }
        if replaceAddressOnNextKey, text == "https://" { address.text = text; replaceAddressOnNextKey = false; return }
        if ["youtube.com", "google.com", "twitch.tv"].contains(text) {
            loadText(text)
        } else { insertKeyboardText(text) }
    }

    private func insertKeyboardText(_ text: String) {
        if inputTarget == .webpage { editWebInput(operation: "insert", text: text); return }
        if replaceAddressOnNextKey {
            address.text = text
            replaceAddressOnNextKey = false
        } else {
            address.text = (address.text ?? "") + text
        }
    }

    private func editWebInput(operation: String, text: String) {
        // Only the MAIN document's focused form element is supported. A field
        // inside a cross-origin iframe can require a platform input API we do
        // not have in this experimental car window.
        let js = "return window.__driveplayEditInput(operation, text);"
        currentWebView.callAsyncJavaScript(
            js,
            arguments: ["operation": operation, "text": text],
            in: nil,
            in: .page
        ) { [weak self] (result: Result<Any, Error>) in
            switch result {
            case .success(let value):
                if let changed = value as? Bool, !changed {
                    self?.showStatus("This webpage field is unavailable for the car keyboard")
                }
            case .failure(let error):
                NSLog("DRIVEPLAY-WEB web form keyboard error: %@", error.localizedDescription)
                self?.showStatus("This webpage field cannot be edited")
            }
        }
    }

    // MARK: - Main-document form input bridge

    private static let focusTrackingScript = #"""
    (() => {
      if (window.__driveplayEditInput) return;
      let lastField = null;
      const editable = e => !!e && (e.matches?.('input,textarea') || e.isContentEditable);
      document.addEventListener('focusin', event => {
        let el = event.target;
        if (!editable(el)) return;
        if (el.matches?.('input')) {
          const type = (el.type || '').toLowerCase();
          if (['checkbox','radio','file','hidden','button','submit','reset','range','color','date','time','datetime-local'].includes(type)) return;
        }
        lastField = el;
        try { window.webkit.messageHandlers.driveplayFocus.postMessage({event:'focus'}); } catch (_) {}
      }, true);
      window.__driveplayEditInput = (operation, text) => {
        const el = lastField;
        if (!el || !el.isConnected || !editable(el)) return false;
        el.focus({preventScroll:false});
        if (operation === 'submit') {
          el.dispatchEvent(new Event('change', {bubbles:true}));
          if (el.form && el.form.requestSubmit) el.form.requestSubmit();
          else el.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter',bubbles:true}));
          return true;
        }
        if (el.isContentEditable) {
          if (operation === 'clear') { el.textContent=''; }
          else if (operation === 'backspace') { document.execCommand('delete', false); }
          else { document.execCommand('insertText', false, String(text)); }
          el.dispatchEvent(new InputEvent('input',{bubbles:true}));
          return true;
        }
        const value = el.value || '';
        const start = el.selectionStart ?? value.length;
        const end = el.selectionEnd ?? value.length;
        let next, cursor;
        if (operation === 'clear') { next=''; cursor=0; }
        else if (operation === 'backspace') {
          let from = start;
          if (start === end && start > 0) from = start-1;
          next = value.slice(0,from) + value.slice(end);
          cursor = from;
        } else {
          const inserted = String(text);
          next = value.slice(0,start) + inserted + value.slice(end);
          cursor = start + inserted.length;
        }
        const descriptor = Object.getOwnPropertyDescriptor(
          el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value');
        if (descriptor?.set) descriptor.set.call(el, next); else el.value = next;
        try { el.setSelectionRange(cursor,cursor); } catch (_) {}
        el.dispatchEvent(new InputEvent('input', {bubbles:true,inputType:'insertText',data:String(text)}));
        return true;
      };
    })();
    """#

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard message.name == "driveplayFocus",
              !tabs.isEmpty,
              message.webView === currentWebView,
              !gate.isLocked else { return }
        inputTarget = .webpage
        replaceAddressOnNextKey = false
        setKeyboard(visible: true, target: .webpage)
    }

    // MARK: - WebKit navigation + popup

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !tabs.isEmpty, webView === currentWebView else { return }
        clearStatus()
        updateToolbar()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !tabs.isEmpty, webView === currentWebView else { return }
        webCrashRetries.remove(ObjectIdentifier(webView))
        clearStatus()
        updateToolbar()
        NSLog("DRIVEPLAY-WEB loaded URL=%@", webView.url.map { CredentialRedactor.safeForLog($0) } ?? "-")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }

    private func showNavigationError(_ error: Error, in webView: WKWebView) {
        guard !tabs.isEmpty, webView === currentWebView else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        showStatus(error.localizedDescription)
        NSLog("DRIVEPLAY-WEB navigation error=%@", error.localizedDescription)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        if webCrashRetries.insert(key).inserted { webView.reload() }
        else { showStatus("Web process crashed twice. Choose another page.") }
    }

    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        createTab(url: url)
        return nil
    }

    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrame else {
            decisionHandler(.allow)
            return
        }
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["http", "https", "about", "blob"].contains(scheme) ? .allow : .cancel)
    }
}

/// Conservative parked-use gate for the experimental browser.
/// Location and zero speed do NOT prove the gear is in Park: this is only a
/// supplementary guard. Production car-integrated apps must enforce actual
/// vehicle/safety state wherever the platform exposes it.
final class CarBrowserParkingGate: NSObject, CLLocationManagerDelegate {
    var onChange: ((Bool, String, Bool) -> Void)?
    private let manager = CLLocationManager()
    private var timer: Timer?
    private var confirmedByUser = false
    private var lastSample: Date?
    private var lastMotionTime: Date?
    private var lastSpeed: CLLocationSpeed = -1.0
    private var eligible = false

    // Locked if user has not confirmed, vehicle is ineligible, or motion was detected
    var isLocked: Bool {
        if !eligible || isMotionActive {
            return true
        }
        return !confirmedByUser
    }

    private var isMotionActive: Bool {
        if lastSpeed > 0.8 { return true }
        if let motionTime = lastMotionTime, Date().timeIntervalSince(motionTime) < 15.0 {
            return true
        }
        return false
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.checkStaleness()
        }
        reportCurrentState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
    }

    func confirmParked() {
        // Strictly prevent user confirmation from bypassing vehicle movement or unverified state
        guard !isMotionActive else {
            reportCurrentState(overrideReason: "Cannot confirm parked: vehicle movement detected.")
            return
        }
        guard eligible else {
            reportCurrentState(overrideReason: "Acquiring GPS fix: stationary location required.")
            return
        }
        guard let last = lastSample, Date().timeIntervalSince(last) < 10.0 else {
            reportCurrentState(overrideReason: "GPS signal stale: waiting for fresh stationary fix.")
            return
        }
        confirmedByUser = true
        reportCurrentState()
    }

    private func checkStaleness() {
        // If GPS is stale (> 12 seconds without update), we cannot verify vehicle is stationary
        if let last = lastSample, Date().timeIntervalSince(last) > 12.0 {
            eligible = false
            reportCurrentState(overrideReason: "GPS fix lost. Stationary confirmation paused.")
            return
        }
        // If motion cooldown expired, allow confirmation again
        if let motionTime = lastMotionTime, Date().timeIntervalSince(motionTime) >= 15.0 {
            if lastSpeed >= 0 && lastSpeed <= 0.8 {
                eligible = true
                reportCurrentState()
            }
        }
    }

    private func reportCurrentState(overrideReason: String? = nil) {
        let motion = isMotionActive
        let locked = isLocked
        let mayConfirm = eligible && !motion

        let reason: String
        if let override = overrideReason {
            reason = override
        } else if motion {
            let speedKmh = max(0, lastSpeed * 3.6)
            reason = "Vehicle motion detected (\(String(format: "%.1f", speedKmh)) km/h).\nBrowser is locked for driving safety."
        } else if !eligible {
            reason = "Awaiting confirmed stationary GPS signal..."
        } else if !confirmedByUser {
            reason = "Vehicle appears stationary.\nPlease confirm parked status to browse."
        } else {
            reason = "Parked use active."
        }

        onChange?(locked,
                  locked ? "Browser available only while parked.\n" + reason : reason,
                  mayConfirm && !confirmedByUser)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastSample = Date()
        lastSpeed = location.speed

        // If speed indicates driving motion (> 0.8 m/s ≈ 2.9 km/h), lock immediately
        if location.speed > 0.8 {
            eligible = false
            confirmedByUser = false
            lastMotionTime = Date()
            reportCurrentState()
            return
        }

        // Stationary (speed 0 to 0.8 m/s) with valid accuracy
        if location.speed >= 0 && location.speed <= 0.8 && location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 {
            if let motionTime = lastMotionTime, Date().timeIntervalSince(motionTime) < 15.0 {
                // In safety cooldown period
                eligible = false
            } else {
                eligible = true
            }
        } else if location.speed < 0 {
            // Speed unavailable: conservative fallback
            eligible = false
        }
        reportCurrentState()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            eligible = false
            confirmedByUser = false
            reportCurrentState(overrideReason: "Location permission required to verify parked status.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location manager error: fail safe
        eligible = false
        reportCurrentState(overrideReason: "GPS error: cannot verify parked state.")
    }
}
