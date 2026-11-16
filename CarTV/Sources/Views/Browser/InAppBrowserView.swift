import SwiftUI
import WebKit

public struct BookmarkItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let subtitle: String?
    public let urlString: String
    public let iconBgColor: Color
    public let systemImage: String?
    public let labelText: String?
    public let labelColor: Color
    
    public init(
        name: String,
        subtitle: String? = nil,
        urlString: String,
        iconBgColor: Color = .clear,
        systemImage: String? = nil,
        labelText: String? = nil,
        labelColor: Color = .white
    ) {
        self.name = name
        self.subtitle = subtitle
        self.urlString = urlString
        self.iconBgColor = iconBgColor
        self.systemImage = systemImage
        self.labelText = labelText
        self.labelColor = labelColor
    }
}

/// The browser's two search boxes.
///
/// The address bar at the bottom and the start page's own search box are two
/// text fields — and they used to share **one** piece of state, so what the
/// user typed in one of them appeared in the other, and the change handlers
/// wiped it. Each box keeps its own text here.
public struct BrowserAddressBoxes: Equatable {

    /// The address bar's text.
    public var address: String = ""
    /// The start page's own search box.
    public var startPageQuery: String = ""

    /// Fills the address bar with the page's address when the user taps it.
    ///
    /// **Only while it is empty.** A user who has already typed keeps what
    /// they typed: filling the field over their text is what made the typing
    /// look like it did nothing at all.
    public mutating func beginEditingAddress(currentURL: String) {
        if address.isEmpty { address = currentURL }
    }

    /// The text a submit opens.
    ///
    /// The text is taken **first**: giving the keyboard up empties the box,
    /// and a box that is read after it was emptied opens nothing.
    public static func submitted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct InAppBrowserView: View {
    @ObservedObject var tabManager = BrowserTabManager.shared
    @ObservedObject var adBlocker = AdBlockerEngine.shared
    @ObservedObject private var share = ScreenShareService.shared

    @State private var boxes = BrowserAddressBoxes()
    @State private var showAdBlockInfo: Bool = false
    @FocusState private var isAddressFieldFocused: Bool
    @FocusState private var isStartPageFieldFocused: Bool
    
    // MARK: - Bookmarks Catalog
    //
    // The sites live in `BrowserCatalog`, so the car's browser tab offers the
    // same list as the phone.

    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Content Area: Web View OR Native Bookmarks List
            if let activeTab = tabManager.activeTab, !tabManager.activeTabURL.isEmpty {
                ActiveTabWebViewContainer(tab: activeTab)
                    .id(activeTab.id)
            } else {
                nativeBookmarksListView
            }
            
            // Safari Native Bottom Search, Tab Add & Navigation Controls
            safariBottomBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            // The car is waiting for this page — the car has no web view of
            // its own, so the page reaches it through the phone's screen
            // share, and iOS always asks the user to start one.
            carWaitingBanner
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .navigationTitle(currentNavTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Top Bar: Ad Shield & Start Page Home button
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAdBlockInfo = true
                } label: {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.green)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                if !tabManager.activeTabURL.isEmpty {
                    Button {
                        withAnimation {
                            tabManager.activeTab?.urlString = ""
                            tabManager.updateActiveTabState(url: "")
                            boxes.address = ""
                            boxes.startPageQuery = ""
                        }
                    } label: {
                        Image(systemName: "house")
                    }
                }
            }
        }
        .sheet(isPresented: $tabManager.isViewingTabGrid) {
            NativeSafariTabManagerSheet()
        }
        .sheet(isPresented: $showAdBlockInfo) {
            nativeAdBlockerInfoSheet
        }
        .onAppear {
            syncAddressFieldWithActiveTab()
        }
        .onChange(of: isAddressFieldFocused) { focused in
            if focused {
                // The bar shows the page's address so the user can edit it —
                // but **only while it is empty**. A user who has already
                // started typing keeps what they typed: filling the field
                // over their text is what made the typing look like it did
                // nothing at all.
                boxes.beginEditingAddress(currentURL: tabManager.activeTabURL)
            } else {
                syncAddressFieldWithActiveTab()
            }
        }
        .onChange(of: tabManager.activeTabURL) { newURL in
            if !isAddressFieldFocused {
                syncAddressFieldWithActiveTab()
            }
        }
    }
    
    /// The car is waiting for the page the user opened on it.
    ///
    /// The picker is the only way to start a share: iOS always asks the
    /// **user**, and the car's screen is not a touch screen — so the button
    /// has to be on the phone.
    @ViewBuilder
    private var carWaitingBanner: some View {
        if let page = share.pendingCarPage {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .foregroundColor(CarTVTheme.accent)
                    Text("The car is waiting for this page")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CarTVTheme.textPrimary)
                    Spacer()
                }
                Text(page)
                    .font(.system(size: 12))
                    .foregroundColor(CarTVTheme.textSecondary)
                    .lineLimit(1)
                BroadcastPickerView()
                    .frame(height: 44)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                Text("Tap the button above and choose the DrivePlay screen relay — the page then appears on the car's display.")
                    .font(.system(size: 11))
                    .foregroundColor(CarTVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        }
    }

    private func syncAddressFieldWithActiveTab() {
        boxes.address = ""
    }
    
    private var displayAddressText: String {
        let u = tabManager.activeTabURL
        if u.isEmpty {
            return "Search or enter website"
        }
        if let host = URL(string: u)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return u
    }
    
    private var canGoBack: Bool {
        return (tabManager.activeTab?.canGoBack == true) || !tabManager.activeTabURL.isEmpty
    }
    
    private var canGoForward: Bool {
        return tabManager.activeTab?.canGoForward == true
    }
    
    private var currentNavTitle: String {
        if let activeTab = tabManager.activeTab, !tabManager.activeTabURL.isEmpty {
            return activeTab.title.isEmpty ? displayAddressText : activeTab.title
        }
        return "Browser"
    }
    
    // MARK: - Safari Native Bottom Bar (Editing & Browsing Modes, Zero UI Collisions)
    
    private var safariBottomBar: some View {
        HStack(spacing: 8) {
            if !isAddressFieldFocused {
                // 1. Back Button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        tabManager.activeTab?.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(canGoBack ? .primary : Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canGoBack)
                
                // 2. Forward Button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        tabManager.activeTab?.goForward()
                    }
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(canGoForward ? .primary : Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!canGoForward)
            }
            
            // 3. Address Capsule with Permanent Interactive Search Field
            HStack(spacing: 6) {
                Image(systemName: tabManager.activeTabURL.isEmpty ? "magnifyingglass" : "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField(
                    tabManager.activeTabURL.isEmpty ? "Search or enter address" : displayAddressText,
                    text: $boxes.address
                )
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .focused($isAddressFieldFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .onSubmit {
                    submitAddress()
                }
                
                if !boxes.address.isEmpty {
                    Button {
                        boxes.address = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    
                    Button {
                        submitAddress()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.accentColor)
                            .frame(width: 26, height: 26)
                    }
                } else if !isAddressFieldFocused {
                    if let activeTab = tabManager.activeTab, activeTab.isLoading {
                        Button {
                            activeTab.stopLoading()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                    } else if !tabManager.activeTabURL.isEmpty {
                        Button {
                            tabManager.activeTab?.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(12)
            
            if isAddressFieldFocused {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isAddressFieldFocused = false
                        syncAddressFieldWithActiveTab()
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // 4. Quick New Tab (+)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tabManager.createNewTab(urlString: "", dismissTabGrid: false)
                        boxes.address = ""
                        isAddressFieldFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                
                // 5. Tabs Switcher Button [N]
                Button {
                    tabManager.isViewingTabGrid = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 1.6)
                            .frame(width: 22, height: 22)
                        
                        Text("\(tabManager.tabs.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAddressFieldFocused)
    }
    
    // MARK: - Native Bookmarks List
    
    private var nativeBookmarksListView: some View {
        List {
            // Direct Top Search Bar for the Start Page
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search Google or type a web address...", text: $boxes.startPageQuery)
                        .font(.system(size: 16))
                        .focused($isStartPageFieldFocused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .onSubmit {
                            submitAddress(boxes.startPageQuery)
                        }

                    if !boxes.startPageQuery.isEmpty {
                        Button {
                            submitAddress(boxes.startPageQuery)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Search or Enter Website")
            }
            
            Section("Live & Sports") {
                ForEach(BrowserCatalog.liveAndSports) { item in
                    bookmarkRow(item)
                }
            }

            Section("Games & Tools") {
                ForEach(BrowserCatalog.gamesAndTools) { item in
                    bookmarkRow(item)
                }
            }

            Section("Video & Music") {
                ForEach(BrowserCatalog.videoAndMusic) { item in
                    bookmarkRow(item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 68)
        }
    }
    
    @ViewBuilder
    private func bookmarkRow(_ item: BookmarkItem) -> some View {
        Button {
            print("[InAppBrowserView] Tapped bookmark: \(item.name) -> \(item.urlString)")
            loadURL(item.urlString)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.iconBgColor)
                        .frame(width: 34, height: 34)
                    
                    if let iconName = item.systemImage {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(item.labelColor)
                    } else if let label = item.labelText {
                        Text(label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(item.labelColor)
                    }
                }
                
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Direct Safari Search / URL Load
    
    private func loadURL(_ rawURL: String) {
        boxes.address = rawURL
        withAnimation {
            tabManager.loadURLInActiveTab(rawURL)
        }
    }
    
    private func submitAddress() {
        submitAddress(boxes.address)
    }

    /// Opens what the user typed.
    ///
    /// The text is taken **first**: giving the keyboard up empties the field,
    /// and a field that is read after it was emptied opens nothing.
    private func submitAddress(_ text: String) {
        guard let trimmed = BrowserAddressBoxes.submitted(text) else { return }

        isAddressFieldFocused = false
        isStartPageFieldFocused = false

        withAnimation {
            tabManager.loadURLInActiveTab(trimmed)
        }
    }
    
    // MARK: - Native Ad Blocker Info Sheet (Clean for Normal Users)
    
    private var nativeAdBlockerInfoSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.checkered")
                            .font(.largeTitle)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(adBlocker.isEnabled ? "Ad Blocker Active" : "Ad Blocker Off")
                                .font(.headline)
                            Text(adBlocker.isEnabled
                                 ? "Your browsing is fast, clean, and protected."
                                 : "Ads and trackers are not being blocked.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Protection") {
                    Toggle("Block ads and trackers", isOn: Binding(
                        get: { adBlocker.isEnabled },
                        set: { newValue in
                            adBlocker.setEnabled(newValue)
                        }
                    ))
                }

                // A site that needs a captcha to log in has to be let
                // through — that is the one thing the blocker cannot decide
                // for the user.
                if let site = currentSite {
                    Section("This Site") {
                        Toggle("Block ads on \(site)", isOn: Binding(
                            get: { !adBlocker.isExempt(site) },
                            set: { block in
                                adBlocker.setExempt(!block, for: site)
                            }
                        ))
                    }
                }

                Section("Protection Status") {
                    Label("Annoying Ads Blocked", systemImage: "checkmark.shield.fill")
                    Label("Popups & Overlays Blocked", systemImage: "checkmark.shield.fill")
                    Label("Trackers Blocked", systemImage: "checkmark.shield.fill")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ad Shield")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showAdBlockInfo = false
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.fraction(0.5)])
    }

    /// The site the active tab is on — the key a site's exemption is
    /// remembered by.
    private var currentSite: String? {
        guard let url = tabManager.activeTab?.webView.url else { return nil }
        return AdBlockerEngine.siteKey(for: url)
    }
}

// MARK: - The web view itself

public struct WebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView

    public func makeUIView(context: Context) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        uiView.setNeedsLayout()
    }
}

// MARK: - Active Tab Web View Container (Observes Tab Directly for Instant Updates)

public struct ActiveTabWebViewContainer: View {
    @ObservedObject var tab: BrowserTabItem
    
    public init(tab: BrowserTabItem) {
        self.tab = tab
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(webView: tab.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.horizontal)
            
            if tab.isLoading {
                ProgressView(value: tab.progress, total: 1.0)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 1.5, anchor: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 68)
        }
        .onAppear {
            if tab.webView.url == nil && !tab.urlString.isEmpty {
                tab.load(tab.urlString)
            }
        }
    }
}

// MARK: - Apple Native Safari Multi-Tab Deck Manager Sheet

public struct NativeSafariTabManagerSheet: View {
    @ObservedObject var tabManager = BrowserTabManager.shared
    @Environment(\.dismiss) var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                ForEach(tabManager.tabs) { tab in
                    let isCurrent = (tab.id == tabManager.activeTab?.id)
                    
                    HStack(spacing: 12) {
                        Button {
                            tabManager.selectTab(id: tab.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.urlString.isEmpty ? "house.fill" : "safari")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.title.isEmpty ? "Start Page" : tab.title)
                                        .font(.body.weight(isCurrent ? .bold : .regular))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                
                                    Text(tab.urlString.isEmpty ? "Speed Dial Bookmarks" : tab.urlString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // Close Tab Button
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                tabManager.closeTab(id: tab.id)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { indexSet in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        for index in indexSet.sorted(by: >) {
                            tabManager.closeTab(at: index)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tabs (\(tabManager.tabs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Native System Button: + New Tab (Keeps the sheet OPEN so user can see it added)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            tabManager.createNewTab(urlString: "", dismissTabGrid: false)
                        }
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                }
                
                // Native System Button: Done
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
