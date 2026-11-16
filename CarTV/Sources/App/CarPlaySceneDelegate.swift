import Foundation
import CarPlay
import UIKit
import Combine

/// Drives the CarPlay scene.
///
/// CarPlay renders **templates only**: no public header in `CarPlay.framework` exposes
/// `UIViewController`, so there is no supported way to put a custom view on the car
/// screen. The whole car UI is therefore built from `CPListTemplate`s, and playback is
/// driven through `PlaybackManager` plus the system now-playing template.
///
/// The car's screen is a tab bar with four tabs — Home, Favorites, Cast and Browser.
/// The templates live in `CarPlayTemplates`; this delegate owns them, keeps them in
/// step with the app's state and carries out what a row asks for.
///
/// This delegate must never touch `CPWindow.rootViewController` — CarPlay owns that
/// window and its template stack.
@objc(CarPlaySceneDelegate)
public final class CarPlaySceneDelegate: UIResponder,
    CPTemplateApplicationSceneDelegate,
    CPTabBarTemplateDelegate,
    CPSearchTemplateDelegate,
    CarPlayTabActions {

    public static private(set) var shared: CarPlaySceneDelegate?
    private var interfaceController: CPInterfaceController?
    public var carWindow: CPWindow?
    private var cancellables = Set<AnyCancellable>()

    private var tabBarTemplate: CPTabBarTemplate?
    private var homeTemplate: CPListTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var castTemplate: CPListTemplate?
    private var browserTemplate: CPListTemplate?
    private var searchTemplate: CPSearchTemplate?
    /// The Browser tab's own delegate — the search field in the **pushed**
    /// address bar is the car's address bar.
    private var browserSearch: CarPlayBrowserSearch?
    /// The car's address bar — the only CarPlay chrome with a text field.
    ///
    /// It is **pushed** onto the stack: the tab bar rejects a search template
    /// (`-validateTemplates:` raises an `NSException` and the app dies).
    private var browserAddressBar: CPSearchTemplate?

    // MARK: - Scene connection

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        connect(interfaceController: interfaceController, window: window)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let win = templateApplicationScene.carWindow
        connect(interfaceController: interfaceController, window: win)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        disconnect()
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        disconnect()
    }

    private func connect(interfaceController: CPInterfaceController, window: CPWindow?) {
        NSLog("DRIVEPLAY CarPlay scene connected")
        Self.shared = self
        self.interfaceController = interfaceController
        self.carWindow = window
        window?.overrideUserInterfaceStyle = .dark

        // The artwork has to be drawn for the **car's** screen — its scale is
        // not the phone's.
        CarPlayArtwork.displayScale = interfaceController.carTraitCollection.displayScale

        let store = PlaylistStore.shared
        let built = Date()
        let home = Self.makeTemplate(tab: .home,
                                     sections: CarPlayTemplates.homeSections(groups: store.allGroups,
                                                                          channels: store.channels,
                                                                          owner: self,
                                                                          prefersVideo: Self.isEntitledToVideo))
        let favorites = Self.makeTemplate(tab: .favorites,
                                          sections: CarPlayTemplates.favoritesSections(channels: store.favoriteChannels,
                                                                                     owner: self,
                                                                                     prefersVideo: Self.isEntitledToVideo))
        let cast = Self.makeTemplate(tab: .cast,
                                     sections: CarPlayTemplates.castSections(state: currentCastState(),
                                                                           owner: self,
                                                                           prefersVideo: Self.isEntitledToVideo))
        // The Browser tab is a **list**: the way into the address bar, the page
        // the phone shows now and the app's own sites. The address bar itself
        // is a search template, and the tab bar rejects one — so it is pushed
        // onto the stack instead.
        let browserSearchDelegate = browserSearch ?? CarPlayBrowserSearch()
        browserSearch = browserSearchDelegate
        browserSearchDelegate.dismissAddressBar = { [weak self] in self?.popBrowserAddressBar() }
        let browser = Self.makeTemplate(tab: .browser,
                                        sections: CarPlayTemplates.browserSections(
                                            currentURL: "",
                                            owner: self))
        NSLog("DRIVEPLAY car screen: scale %.2f, card %.0fx%.0f, row %.0fx%.0f, " +
              "car allows %d items in %d sections; built in %.0f ms",
              CarPlayArtwork.displayScale,
              CarPlayArtwork.cardSize.width, CarPlayArtwork.cardSize.height,
              CarPlayArtwork.rowSize.width, CarPlayArtwork.rowSize.height,
              CPListTemplate.maximumItemCount, CPListTemplate.maximumSectionCount,
              Date().timeIntervalSince(built) * 1000)

        home.leadingNavigationBarButtons = [
            CPBarButton(title: "Search", handler: { [weak self] _ in self?.pushChannelSearch() })
        ]
        if let magImage = UIImage(systemName: "magnifyingglass") {
            home.trailingNavigationBarButtons = [
                CPBarButton(image: magImage, handler: { [weak self] _ in self?.pushChannelSearch() })
            ]
            browser.trailingNavigationBarButtons = [
                CPBarButton(image: magImage, handler: { [weak self] _ in self?.pushBrowserAddressBar() })
            ]
        }
        home.emptyViewTitleVariants = ["No channels"]
        home.emptyViewSubtitleVariants = ["Add a playlist source in the DrivePlay app"]
        favorites.emptyViewTitleVariants = ["No favorites yet"]
        favorites.emptyViewSubtitleVariants = ["Add a favorite on the phone — it appears here at once"]

        self.homeTemplate = home
        self.favoritesTemplate = favorites
        self.castTemplate = cast
        self.browserTemplate = browser

        let bar = Self.makeTabBar([home, favorites, cast, browser])
        bar.delegate = self
        tabBarTemplate = bar

        interfaceController.setRootTemplate(bar, animated: false) { success, error in
            if !success {
                NSLog("DRIVEPLAY setRootTemplate failed: %@", String(describing: error))
            }
        }

        observeState()

        // A car is there. The picture can go to it — and the button on the
        // phone stops asking the user to pick a route, because there is
        // nothing left to pick.
        PlaybackManager.shared.isCarConnected = true

        // A picture that is **already on the car's display** stays there: the
        // phone stops drawing it, so it is not shown twice. A picture that is
        // still on the phone stays on the phone — it moves when the user says
        // so, not because the car happened to connect.
        if PlaybackManager.shared.isPlayingOnCar {
            PlaybackManager.shared.handOffToCar()
        }
    }

    private func disconnect() {
        NSLog("DRIVEPLAY CarPlay scene disconnected")
        if Self.shared === self { Self.shared = nil }
        cancellables.removeAll()
        // There is no car any more: the picture cannot go there, so the button
        // on the phone falls back to the system's list of displays — and a
        // picture that was on the car's display comes back to the phone.
        PlaybackManager.shared.carDisconnected()
        // Nobody is left to watch the stream.
        ScreenShareService.shared.stop()
        ScreenShareService.shared.stopRelay()
        interfaceController = nil
        carWindow = nil
        tabBarTemplate = nil
        homeTemplate = nil
        favoritesTemplate = nil
        castTemplate = nil
        browserTemplate = nil
        searchTemplate = nil
        browserAddressBar = nil
    }

    // MARK: - The tabs

    /// A tab's template — the title and the icon the tab bar shows.
    static func makeTemplate(tab: CarPlayTab, sections: [CPListSection]) -> CPListTemplate {
        let template = CPListTemplate(title: tab.rawValue, sections: sections)
        template.tabTitle = tab.rawValue
        template.tabImage = tab.image
        return template
    }

    /// The tab bar — the four tabs, all of them **lists**.
    ///
    /// The parameter type is the pin: `CPTabBarTemplate(templates:)` raises an
    /// `NSException` when one of its templates is a search template (the
    /// browser's address bar used to be one, and the app died at every scene
    /// connect), so the tab bar takes lists only. The compiler refuses
    /// anything else.
    static func makeTabBar(_ templates: [CPListTemplate]) -> CPTabBarTemplate {
        CPTabBarTemplate(templates: templates)
    }

    private func observeState() {
        // The catalogue changes whenever a source is added or a favourite is toggled.
        PlaylistStore.shared.$channels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCatalogue() }
            .store(in: &cancellables)

        // The picture and the playback change on their own.
        PlaybackManager.shared.$isPlayingOnCar
            .combineLatest(PlaybackManager.shared.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCast() }
            .store(in: &cancellables)

        // A player that comes or goes changes what the Cast tab may offer:
        // the picture rows need one.
        PlaybackManager.shared.$player
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCast() }
            .store(in: &cancellables)

        // The share has a state of its own.
        ScreenShareService.shared.$state
            .combineLatest(ScreenShareService.shared.$playlistURL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCast() }
            .store(in: &cancellables)

    }

    /// The catalogue and the favourites are one thing: they come from the same
    /// list, so both tabs are rebuilt together.
    private func refreshCatalogue() {
        // The search rows carry the names the catalogue had — a channel that
        // was renamed has to be found under its new name.
        searchRows.removeAll()
        searchRowOrder.removeAll()

        let store = PlaylistStore.shared
        homeTemplate?.updateSections(CarPlayTemplates.homeSections(groups: store.allGroups,
                                                                   channels: store.channels,
                                                                   owner: self,
                                                                   prefersVideo: Self.isEntitledToVideo))
        favoritesTemplate?.updateSections(CarPlayTemplates.favoritesSections(channels: store.favoriteChannels,
                                                                            owner: self,
                                                                            prefersVideo: Self.isEntitledToVideo))
    }

    private func refreshCast() {
        castTemplate?.updateSections(CarPlayTemplates.castSections(state: currentCastState(),
                                                                  owner: self,
                                                                  prefersVideo: Self.isEntitledToVideo))
    }

    private func refreshBrowser() {
        browserTemplate?.updateSections(CarPlayTemplates.browserSections(
            currentURL: "",
            owner: self
        ))
    }

    /// The state the Cast tab shows — read from the app, not guessed.
    private func currentCastState() -> CarPlayCastState {
        let playback = PlaybackManager.shared
        let share = ScreenShareService.shared
        return CarPlayCastState(
            pictureOnCar: playback.isPlayingOnCar,
            isPlaying: playback.isPlaying,
            hasPlayer: playback.player != nil,
            share: share.state,
            shareURL: share.networkPlaylistURL?.absoluteString ?? share.playlistURL?.absoluteString
        )
    }

    /// The tab the user picked is brought up to date.
    public func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if selectedTemplate === homeTemplate {
            refreshCatalogue()
        } else if selectedTemplate === favoritesTemplate {
            refreshCatalogue()
        } else if selectedTemplate === castTemplate {
            refreshCast()
        } else if selectedTemplate === browserTemplate {
            refreshBrowser()
        }
    }

    // MARK: - What a row asks for

    func play(channel: Channel) {
        // `.hidden`: the car owns the UI, so the handset shows no player chrome.
        PlaybackManager.shared.play(channel: channel, presentation: .hidden)
        Self.prepareNowPlaying()
    }

    func pushChannels(title: String, channels: [Channel]) {
        let template = CarPlayTemplates.channelList(title: title,
                                                   channels: channels,
                                                   owner: self,
                                                   prefersVideo: Self.isEntitledToVideo)
        // Every template call carries a completion handler: CarPlay throws an
        // `NSException` when a template call fails and no handler was given, and an
        // uncaught ObjC exception takes the app down.
        interfaceController?.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push channel list failed: %@", String(describing: error))
            }
        }
    }

    /// The categories the Home tab had no room for — the rest of the
    /// catalogue, with the count each of them really has.
    func pushCategories(title: String, categories: [ChannelGroup]) {
        let template = CarPlayTemplates.categoryList(title: title, categories: categories, owner: self)
        interfaceController?.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push category list failed: %@", String(describing: error))
            }
        }
    }

    /// The Home tab's search — a search for a channel.
    ///
    /// It used to be **presented**, and that could never work: `presentTemplate`
    /// accepts an action sheet, an alert and voice control — nothing else — so
    /// the presentation failed every time and the Search button did nothing
    /// at all. A search template is **pushed** onto the stack instead, the
    /// same way the browser's address bar is.
    func pushChannelSearch() {
        guard let controller = interfaceController else { return }
        let template = CPSearchTemplate()
        template.delegate = self
        searchTemplate = template
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push the channel search failed: %@", String(describing: error))
            }
        }
    }

    // MARK: - The car's address bar & discovery

    /// The address bar of the car's browser.
    ///
    /// Pushes a `CPSearchTemplate` onto the CarPlay stack with live search and keyboard input.
    func pushBrowserAddressBar() {
        guard let controller = interfaceController else { return }
        let searchDelegate = browserSearch ?? CarPlayBrowserSearch()
        browserSearch = searchDelegate
        searchDelegate.dismissAddressBar = { [weak self] in self?.popBrowserAddressBar() }
        let template = CPSearchTemplate()
        template.delegate = searchDelegate
        browserAddressBar = template
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push browser address bar failed: %@", String(describing: error))
            }
        }
    }

    /// The address bar goes back to the list it was pushed from.
    private func popBrowserAddressBar() {
        popTopTemplate("the browser address bar")
    }

    /// Goes back one template.
    ///
    /// A search template carries no navigation bar button of its own — it does
    /// not conform to `CPBarButtonProviding` — so the way back is a row of
    /// its own list, or this call.
    private func popTopTemplate(_ what: String = "the template") {
        interfaceController?.popTemplate(animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY pop %@ failed: %@", what, String(describing: error))
            }
        }
    }

    /// A page of the browser opens on the phone.
    func openOnPhone(address: String) {
        handleCarPlayWebSelection(address)
    }

    func openInCarBrowser(address: String) {
        handleCarPlayWebSelection(address)
    }

    func openInCarBrowserWithKeyboard() {
        pushBrowserAddressBar()
    }

    public func pushYouTubeHub() {
        guard let controller = interfaceController else { return }
        
        var items: [CPListItem] = []
        
        let searchItem = CPListItem(text: "Search YouTube...", detailText: "Find live videos and creators", image: UIImage(systemName: "magnifyingglass"))
        searchItem.accessoryType = .disclosureIndicator
        searchItem.handler = { [weak self] _, completion in
            self?.pushBrowserAddressBar()
            completion()
        }
        items.append(searchItem)
        
        let store = PlaylistStore.shared
        let liveStreams = store.channels.filter {
            $0.name.localizedCaseInsensitiveContains("youtube") ||
            $0.name.localizedCaseInsensitiveContains("live") ||
            $0.groupTitle.localizedCaseInsensitiveContains("live")
        }
        
        for ch in liveStreams.prefix(15) {
            let item = CarPlayTemplates.channelItem(ch, owner: self, prefersVideo: Self.isEntitledToVideo)
            items.append(item)
        }
        
        if items.count == 1 {
            let sample = Channel(
                name: "YouTube Live Stream",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "YouTube"
            )
            items.append(CarPlayTemplates.channelItem(sample, owner: self, prefersVideo: Self.isEntitledToVideo))
        }
        
        let section = CPListSection(items: items, header: "YouTube Feeds", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "YouTube", sections: [section])
        
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push YouTube template failed: %@", String(describing: error))
            }
        }
    }

    public func pushGoogleDiscovery() {
        guard let controller = interfaceController else { return }
        
        var items: [CPListItem] = []
        
        let searchItem = CPListItem(text: "Search Google...", detailText: "Enter a query on CarPlay keyboard", image: UIImage(systemName: "magnifyingglass"))
        searchItem.accessoryType = .disclosureIndicator
        searchItem.handler = { [weak self] _, completion in
            self?.pushBrowserAddressBar()
            completion()
        }
        items.append(searchItem)
        
        let newsItem = CPListItem(text: "Top News & Headlines", detailText: "Latest global updates", image: UIImage(systemName: "newspaper.fill"))
        newsItem.accessoryType = .disclosureIndicator
        newsItem.handler = { [weak self] _, completion in
            self?.pushWebSearchResults(query: "News")
            completion()
        }
        items.append(newsItem)
        
        let techItem = CPListItem(text: "Technology & Science", detailText: "Trending tech news", image: UIImage(systemName: "cpu.fill"))
        techItem.accessoryType = .disclosureIndicator
        techItem.handler = { [weak self] _, completion in
            self?.pushWebSearchResults(query: "Technology")
            completion()
        }
        items.append(techItem)
        
        let sportsItem = CPListItem(text: "Sports & Racing", detailText: "Scores and motorsport", image: UIImage(systemName: "flag.checkered.2.crossed"))
        sportsItem.accessoryType = .disclosureIndicator
        sportsItem.handler = { [weak self] _, completion in
            self?.pushWebSearchResults(query: "Sports")
            completion()
        }
        items.append(sportsItem)
        
        let section = CPListSection(items: items, header: "Google Web Discovery", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Google", sections: [section])
        
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push Google template failed: %@", String(describing: error))
            }
        }
    }

    public func pushTwitchHub() {
        guard let controller = interfaceController else { return }
        
        var items: [CPListItem] = []
        
        let searchItem = CPListItem(text: "Search Twitch...", detailText: "Find gaming channels", image: UIImage(systemName: "magnifyingglass"))
        searchItem.accessoryType = .disclosureIndicator
        searchItem.handler = { [weak self] _, completion in
            self?.pushBrowserAddressBar()
            completion()
        }
        items.append(searchItem)
        
        let store = PlaylistStore.shared
        let gamingStreams = store.channels.filter {
            $0.name.localizedCaseInsensitiveContains("gaming") ||
            $0.name.localizedCaseInsensitiveContains("twitch") ||
            $0.name.localizedCaseInsensitiveContains("esport") ||
            $0.groupTitle.localizedCaseInsensitiveContains("gaming")
        }
        
        for ch in gamingStreams.prefix(15) {
            let item = CarPlayTemplates.channelItem(ch, owner: self, prefersVideo: Self.isEntitledToVideo)
            items.append(item)
        }
        
        if items.count == 1 {
            let sample = Channel(
                name: "Twitch Esports Arena Live",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Twitch"
            )
            items.append(CarPlayTemplates.channelItem(sample, owner: self, prefersVideo: Self.isEntitledToVideo))
        }
        
        let section = CPListSection(items: items, header: "Twitch Gaming", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Twitch", sections: [section])
        
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push Twitch template failed: %@", String(describing: error))
            }
        }
    }

    public func pushWebSearchResults(query: String) {
        guard let controller = interfaceController else { return }
        
        let store = PlaylistStore.shared
        let matching = store.channels.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.groupTitle.localizedCaseInsensitiveContains(query)
        }
        
        var items: [CPListItem] = []
        if !matching.isEmpty {
            for ch in matching.prefix(20) {
                items.append(CarPlayTemplates.channelItem(ch, owner: self, prefersVideo: Self.isEntitledToVideo))
            }
        } else {
            let sample = Channel(
                name: "Web Stream: \(query)",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Web Search"
            )
            items.append(CarPlayTemplates.channelItem(sample, owner: self, prefersVideo: Self.isEntitledToVideo))
        }
        
        let section = CPListSection(items: items, header: "Results for \"\(query)\"", sectionIndexTitle: nil)
        let template = CPListTemplate(title: query, sections: [section])
        
        controller.pushTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY push web search results failed: %@", String(describing: error))
            }
        }
    }

    public func handleCarPlayWebSelection(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let lower = trimmed.lowercased()
        if lower.contains("youtube") {
            pushYouTubeHub()
            return
        } else if lower.contains("google") {
            pushGoogleDiscovery()
            return
        } else if lower.contains("twitch") {
            pushTwitchHub()
            return
        }
        
        if trimmed.hasSuffix(".m3u8") || trimmed.hasSuffix(".mp4") {
            let ch = Channel(
                name: "Web Stream",
                streamURL: URL(string: trimmed) ?? URL(string: "https://\(trimmed)")!,
                groupTitle: "Web Stream"
            )
            play(channel: ch)
            return
        }
        
        pushWebSearchResults(query: trimmed)
    }

    /// The picture moves between the phone and the car.
    func togglePicture() {
        if PlaybackManager.shared.isPlayingOnCar {
            PlaybackManager.shared.castToPhone()
        } else {
            PlaybackManager.shared.handOffToCar()
        }
        refreshCast()
    }

    func togglePlayback() {
        PlaybackManager.shared.togglePlayPause()
        refreshCast()
    }

    func startScreenShare() {
        ScreenShareService.shared.startForTheCar()
        Self.prepareNowPlaying()
        refreshCast()
    }

    func stopScreenShare() {
        // The row is the only stop control on the car, so it has to end the
        // picture — stopping the listener alone leaves the share running and
        // the car showing it.
        ScreenShareService.shared.stop()
        ScreenShareService.shared.stopRelay()
        refreshCast()
    }

    // MARK: - Playback signal

    /// The playback signal a row carries.
    ///
    /// `.video` means "present video if available, otherwise show now playing" —
    /// but the system refuses the playback when the app does not carry the
    /// `com.apple.developer.carplay-video` entitlement ("presentation is video
    /// but app does not have the video entitlement"), so the app only asks for
    /// video when this build can have it.
    @available(iOS 26.4, *)
    static func playbackConfiguration(prefersVideo: Bool) -> CPPlaybackConfiguration {
        CPPlaybackConfiguration(
            preferredPresentation: prefersVideo ? .video : .audio,
            playbackAction: .play,
            elapsedTime: .zero,
            duration: .zero
        )
    }

    /// True when this build carries the CarPlay video entitlement.
    ///
    /// The capability is Apple-granted and it lives on the app id, so a build
    /// is either signed with it or not — and a build that asks for it cannot be
    /// signed without it. The build says which, through the Info.plist.
    public static var isEntitledToVideo: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "CarPlayCategory") as? String) == "video"
    }

    /// Prepares the now-playing screen — **the system presents it, not the app**.
    ///
    /// The rows carry a `playbackConfiguration`, and CarPlay shows the media
    /// presentation itself when the item is selected ("the style of media
    /// presentation shown after selecting the item"), presenting the shared
    /// now-playing template on the app's behalf. That is also where the video
    /// surface is drawn, so the app must not put a template of its own there.
    ///
    /// Presenting the now-playing template from here was the crash: `presentTemplate`
    /// accepts only action sheets, alerts and voice control, so the presentation
    /// failed — and CarPlay **throws an `NSException` when a template call fails and
    /// no completion handler was given**, which took the app down on every row tap.
    static func prepareNowPlaying() {
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([])
    }

    // MARK: - Channel picker

    /// The channel picker is a **list**, not a grid.
    ///
    /// Only `CPListItem` carries a `playbackConfiguration`, and that is how CarPlay is
    /// told a selection is video. `CPGridButton` has no such property, so a grid of
    /// channels could never ask the system for the video surface.
    static func makeChannelTemplate(group: ChannelGroup,
                                     owner: CarPlayTabActions?,
                                     prefersVideo: Bool = isEntitledToVideo) -> CPListTemplate {
        CarPlayTemplates.channelList(title: group.name,
                                     channels: group.channels,
                                     owner: owner,
                                     prefersVideo: prefersVideo)
    }

    // MARK: - Search

    /// The channel each result of the last search stands for.
    ///
    /// A search result is **not** a list row: CarPlay hands the selection to
    /// `searchTemplate(_:selectedResult:completionHandler:)` and never calls the
    /// row's own handler, so the app has to know what the result was. The row
    /// only carries the channel's name — two channels can share one — so the
    /// result is remembered by the item itself.
    private var searchResults: [ObjectIdentifier: Channel] = [:]

    /// The rows the channel search offers — built **once** and kept.
    ///
    /// The search template is handed a fresh list on **every keystroke**, and a
    /// row that is built again is a row the car has to be given again — with
    /// its picture, drawn at the car's scale. Thirty of those per keystroke
    /// is what took the CarPlay session down.
    ///
    /// The cache is **bounded**: every row holds a picture, and the whole
    /// catalogue would be a hundred megabytes of them.
    private var searchRows: [UUID: CPListItem] = [:]
    /// The rows in the order they were built — the oldest one goes first.
    private var searchRowOrder: [UUID] = []
    /// How many rows the search keeps.
    private static let searchRowCapacity = 60
    /// How many channels the search offers.
    private static let searchResultLimit = 30

    /// The row that takes the user back to the list the search was pushed
    /// from.
    ///
    /// A `CPSearchTemplate` does not conform to `CPBarButtonProviding` — it
    /// cannot carry a navigation bar button — so the way back has to be a row
    /// of the search's own list.
    private var searchBackRow: CPListItem?

    public func searchTemplate(_ searchTemplate: CPSearchTemplate,
                               updatedSearchText searchText: String,
                               completionHandler: @escaping ([CPListItem]) -> Void) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let channels = PlaylistStore.shared.channels
        let filtered = query.isEmpty ? channels : channels.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.groupTitle.localizedCaseInsensitiveContains(query) ||
            ($0.tvgId?.localizedCaseInsensitiveContains(query) ?? false)
        }

        var results: [ObjectIdentifier: Channel] = [:]
        var items: [CPListItem] = []

        // The way back — the first row, **always**: a search the user cannot
        // get out of is a dead end, and typing must not take the way out
        // away.
        let back = searchBackRow ?? CPListItem(text: "Back to channels",
                                                detailText: nil,
                                                image: UIImage(systemName: "chevron.backward"))
        searchBackRow = back
        items.append(back)

        for channel in filtered.prefix(Self.searchResultLimit) {
            let item = searchRow(for: channel)
            results[ObjectIdentifier(item)] = channel
            items.append(item)
        }
        searchResults = results
        completionHandler(items)
    }

    public func searchTemplate(_ searchTemplate: CPSearchTemplate,
                               selectedResult item: CPListItem,
                               completionHandler: @escaping () -> Void) {
        if let back = searchBackRow, item === back {
            popTopTemplate()
            completionHandler()
            return
        }
        if let channel = searchResults[ObjectIdentifier(item)] {
            play(channel: channel)
        } else {
            NSLog("DRIVEPLAY the selected search result stands for no channel")
        }
        completionHandler()
    }

    @objc public func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        if let firstChannel = searchResults.values.first {
            play(channel: firstChannel)
            popTopTemplate()
        }
    }

    /// The row for a channel — built the first time it is asked for and kept
    /// until the cache is full.
    private func searchRow(for channel: Channel) -> CPListItem {
        if let item = searchRows[channel.id] { return item }
        let item = CarPlayTemplates.channelItem(channel, owner: self, prefersVideo: Self.isEntitledToVideo)
        searchRows[channel.id] = item
        searchRowOrder.append(channel.id)
        if searchRowOrder.count > Self.searchRowCapacity {
            searchRows[searchRowOrder.removeFirst()] = nil
        }
        return item
    }
}
