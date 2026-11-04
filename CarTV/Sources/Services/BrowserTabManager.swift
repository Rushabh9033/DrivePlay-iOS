import SwiftUI
import WebKit
import Combine

@MainActor
public final class BrowserTabItem: NSObject, Identifiable, ObservableObject, WKNavigationDelegate {
    public let id: UUID
    @Published public var title: String
    @Published public var urlString: String
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var progress: Double = 0.0
    public let webView: WKWebView
    
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    /// True while the tab has reloaded the page once after its web process died.
    private var hasReloadedAfterCrash = false
    
    public init(title: String = "Start Page", urlString: String = "") {
        self.id = UUID()
        self.title = title
        self.urlString = urlString
        
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        AdBlockerEngine.shared.apply(to: config)
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        self.webView = wv
        
        super.init()
        wv.navigationDelegate = self
        setupObservations()
        
        if !urlString.isEmpty {
            load(urlString)
        }
    }
    
    public func load(_ input: String) {
        guard let destination = Self.destination(for: input) else { return }

        // A URL that cannot be built is not loaded at all — and the tab must
        // not be left spinning for ever.
        guard let url = URL(string: destination) else {
            self.isLoading = false
            self.title = "That is not a web address"
            return
        }

        // The URL is not written out as it is: a user can paste one with a
        // password in it, and the device's log is readable by anything
        // attached to the phone.
        print("[BrowserTabItem] Loading destination: \(CredentialRedactor.safeForLog(destination))")
        self.urlString = destination
        self.title = "Loading..."
        self.isLoading = true
        self.canGoBack = true

        AdBlockerEngine.shared.apply(to: webView.configuration)
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        webView.load(request)

        BrowserTabManager.shared.updateActiveTabState(url: destination)
    }

    /// The characters a search term may keep.
    ///
    /// `CharacterSet.urlQueryAllowed` leaves `&`, `=`, `+` and `?` alone — and
    /// those are exactly the characters that break a query: a search for
    /// "a&b=c" would turn into two parameters and the second one would be lost.
    private static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return allowed
    }()

    /// Where an input goes: a URL is a URL, anything else is a search.
    ///
    /// This is the rule the phone's browser follows, and the car's browser
    /// follows the same one — so it lives in one place.
    public static func destination(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        if trimmed.contains(".") && !trimmed.contains(" ") {
            return "https://" + trimmed
        }
        return "https://www.google.com/search?q="
            + (trimmed.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? trimmed)
    }

    public func reload() {
        if webView.url != nil {
            webView.reload()
        } else if !urlString.isEmpty {
            load(urlString)
        }
    }
    
    public func stopLoading() {
        webView.stopLoading()
        isLoading = false
    }
    
    public func goBack() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            urlString = ""
            title = "Start Page"
            canGoBack = false
            canGoForward = false
            BrowserTabManager.shared.updateActiveTabState(url: "")
        }
    }
    
    public func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    private func setupObservations() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.progress = wv.estimatedProgress
                BrowserTabManager.shared.objectWillChange.send()
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let t = wv.title, !t.isEmpty {
                    self.title = t
                    BrowserTabManager.shared.objectWillChange.send()
                }
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let u = wv.url?.absoluteString, !u.isEmpty {
                    self.urlString = u
                    if BrowserTabManager.shared.activeTab?.id == self.id {
                        BrowserTabManager.shared.activeTabURL = u
                    }
                }
                self.canGoBack = wv.canGoBack || !self.urlString.isEmpty
                self.canGoForward = wv.canGoForward
                BrowserTabManager.shared.objectWillChange.send()
            }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = wv.isLoading
                self.canGoBack = wv.canGoBack || !self.urlString.isEmpty
                self.canGoForward = wv.canGoForward
                BrowserTabManager.shared.objectWillChange.send()
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    nonisolated public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = true
            self.canGoBack = webView.canGoBack || !self.urlString.isEmpty
            self.canGoForward = webView.canGoForward
            BrowserTabManager.shared.objectWillChange.send()
        }
    }
    
    nonisolated public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.hasReloadedAfterCrash = false
            self.isLoading = false
            self.canGoBack = webView.canGoBack || !self.urlString.isEmpty
            self.canGoForward = webView.canGoForward
            if let u = webView.url?.absoluteString, !u.isEmpty {
                self.urlString = u
                if BrowserTabManager.shared.activeTab?.id == self.id {
                    BrowserTabManager.shared.activeTabURL = u
                }
            }
            if let t = webView.title, !t.isEmpty {
                self.title = t
            }
            BrowserTabManager.shared.objectWillChange.send()
        }
    }
    
    nonisolated public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.canGoBack = webView.canGoBack || !self.urlString.isEmpty
            self.canGoForward = webView.canGoForward
            BrowserTabManager.shared.objectWillChange.send()
        }
    }
    
    nonisolated public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.canGoBack = webView.canGoBack || !self.urlString.isEmpty
            self.canGoForward = webView.canGoForward
            BrowserTabManager.shared.objectWillChange.send()
        }
    }

    /// The page's web process died — WebKit killed it, usually because the
    /// page used too much memory.
    ///
    /// The tab used to be left with a dead page and nothing else: the process
    /// is gone, so the view shows nothing and never recovers. A reload is
    /// allowed **once** — a reload in a loop is worse than a dead tab, because
    /// the page that killed the process is loaded again, kills it again, and
    /// the app is taken down with it (the watchdog kills an app that stops
    /// answering). A page that dies twice is the page's own fault, so the
    /// tab says so and stops.
    ///
    /// The **address is kept**. Sending the tab back to the start page is the
    /// user's *"it crash the browser tab and redirect tom home screen"* — the
    /// page is thrown away, and the browser looks as if it had never been
    /// asked for it. The tab says what happened instead, and the reload
    /// button in the browser's own bar brings the page back.
    nonisolated public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("DRIVEPLAY the page's web process died")
        Task { @MainActor in
            self.handleWebProcessDeath()
        }
    }

    /// What the tab does when the page's web process died.
    ///
    /// The first death is reloaded **once**; the second is reported and the
    /// address is **kept** — sending the tab back to the start page is the
    /// user's *"it crash the browser tab and redirect tom home screen"*.
    ///
    /// - Returns: `true` when the page was loaded again.
    @discardableResult
    func handleWebProcessDeath() -> Bool {
        if hasReloadedAfterCrash {
            hasReloadedAfterCrash = false
            isLoading = false
            title = "The page crashed"
            BrowserTabManager.shared.objectWillChange.send()
            return false
        }
        hasReloadedAfterCrash = true
        reload()
        return true
    }
    
    deinit {
        progressObservation?.invalidate()
        titleObservation?.invalidate()
        urlObservation?.invalidate()
        loadingObservation?.invalidate()
    }
}

@MainActor
public final class BrowserTabManager: ObservableObject {
    public static let shared = BrowserTabManager()
    
    @Published public var tabs: [BrowserTabItem] = []
    @Published public var activeIndex: Int = 0
    @Published public var activeTabURL: String = ""
    @Published public var isViewingTabGrid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        let initialTab = BrowserTabItem(title: "Start Page", urlString: "")
        self.tabs = [initialTab]
        self.activeIndex = 0
        self.activeTabURL = ""
        setupObservations()
    }
    
    public var activeTab: BrowserTabItem? {
        guard activeIndex >= 0 && activeIndex < tabs.count else { return nil }
        return tabs[activeIndex]
    }
    
    public func updateActiveTabState(url: String) {
        self.activeTabURL = url
        self.objectWillChange.send()
    }
    
    public func loadURLInActiveTab(_ urlString: String) {
        print("[BrowserTabManager] loadURLInActiveTab called with: \(CredentialRedactor.safeForLog(urlString))")
        if tabs.isEmpty {
            createNewTab(urlString: urlString, dismissTabGrid: false)
        } else {
            guard let tab = activeTab else { return }
            tab.load(urlString)
            self.activeTabURL = tab.urlString
            self.objectWillChange.send()
        }
    }
    
    public func createNewTab(urlString: String = "", dismissTabGrid: Bool = false) {
        let newTab = BrowserTabItem(title: urlString.isEmpty ? "Start Page" : "Loading...", urlString: urlString)
        tabs.append(newTab)
        activeIndex = tabs.count - 1
        activeTabURL = urlString
        if dismissTabGrid {
            isViewingTabGrid = false
        }
        setupObservations()
        objectWillChange.send()
    }
    
    public func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let wasActive = index == activeIndex
        tabs.remove(at: index)
        if tabs.isEmpty {
            let emptyTab = BrowserTabItem(title: "Start Page", urlString: "")
            tabs = [emptyTab]
            activeIndex = 0
            activeTabURL = ""
        } else {
            if wasActive {
                // The active tab is gone: the one that took its place (or the
                // one before it) becomes the active one.
                activeIndex = min(activeIndex, tabs.count - 1)
            } else if index < activeIndex {
                // A tab **before** the active one was closed: the active tab
                // moved down by one, and the index has to follow it — otherwise
                // the user is suddenly looking at a different tab.
                activeIndex -= 1
            }
            activeTabURL = tabs[activeIndex].urlString
        }
        setupObservations()
        objectWillChange.send()
    }
    
    public func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTab(at: idx)
    }
    
    public func selectTab(id: UUID) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            activeIndex = idx
            activeTabURL = tabs[idx].urlString
            isViewingTabGrid = false
            objectWillChange.send()
        }
    }
    
    public func closeAllTabs() {
        tabs.removeAll()
        let freshTab = BrowserTabItem(title: "Start Page", urlString: "")
        tabs = [freshTab]
        activeIndex = 0
        activeTabURL = ""
        isViewingTabGrid = false
        setupObservations()
        objectWillChange.send()
    }
    
    private func setupObservations() {
        cancellables.removeAll()
        for tab in tabs {
            tab.objectWillChange
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.objectWillChange.send()
                }
                .store(in: &cancellables)
            // The **new** address, not the old one.
            //
            // `objectWillChange` fires *before* the value changes, so a mirror
            // that reads `tab.urlString` there is always one change behind —
            // and the browser's start page is shown while the page is still
            // there. The publisher carries the value the property is about to
            // take, so it is the one to read.
            tab.$urlString
                .dropFirst()
                .sink { [weak self] newValue in
                    guard let self = self else { return }
                    if self.activeTab?.id == tab.id {
                        self.activeTabURL = newValue
                    }
                }
                .store(in: &cancellables)
        }
    }
}
