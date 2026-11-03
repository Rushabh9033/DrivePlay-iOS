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
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var destination = trimmed
        if destination.lowercased().hasPrefix("http://") || destination.lowercased().hasPrefix("https://") {
            // direct URL
        } else if destination.contains(".") && !destination.contains(" ") {
            destination = "https://" + destination
        } else {
            // Google custom search query
            destination = "https://www.google.com/search?q=" + (destination.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? destination)
        }

        // A URL that cannot be built is not loaded at all — and the tab must
        // not be left spinning for ever.
        guard let url = URL(string: destination) else {
            self.isLoading = false
            self.title = "That is not a web address"
            return
        }

        print("[BrowserTabItem] Loading destination: \(destination)")
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
        print("[BrowserTabManager] loadURLInActiveTab called with: \(urlString)")
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
                    if self.activeTab?.id == tab.id {
                        if self.activeTabURL != tab.urlString {
                            self.activeTabURL = tab.urlString
                        }
                    }
                    self.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
}
