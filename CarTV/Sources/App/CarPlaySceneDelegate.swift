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

    private var interfaceController: CPInterfaceController?
    public var carWindow: CPWindow?
    private var cancellables = Set<AnyCancellable>()

    private var tabBarTemplate: CPTabBarTemplate?
    private var homeTemplate: CPListTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var castTemplate: CPListTemplate?
    private var browserTemplate: CPListTemplate?
    private var searchTemplate: CPSearchTemplate?

    /// The artwork of the channels on the screen arrives one logo at a time — the
    /// screen is rebuilt once the batch has settled.
    private var artworkRefresh: DispatchWorkItem?

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
        connect(interfaceController: interfaceController, window: templateApplicationScene.carWindow)
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
        self.interfaceController = interfaceController
        self.carWindow = window
        window?.overrideUserInterfaceStyle = .dark

        // The artwork has to be drawn for the **car's** screen — its scale is
        // not the phone's.
        CarPlayArtwork.displayScale = interfaceController.carTraitCollection.displayScale

        let store = PlaylistStore.shared
        let home = Self.makeTemplate(tab: .home,
                                     sections: CarPlayTemplates.homeSections(groups: store.allGroups,
                                                                          channels: store.channels,
                                                                          owner: self,
                                                                          prefersVideo: Self.isEntitledToVideo,
                                                                          onArtwork: { [weak self] in self?.scheduleArtworkRefresh() }))
        let favorites = Self.makeTemplate(tab: .favorites,
                                          sections: CarPlayTemplates.favoritesSections(channels: store.favoriteChannels,
                                                                                     owner: self,
                                                                                     prefersVideo: Self.isEntitledToVideo,
                                                                                     onArtwork: { [weak self] in self?.scheduleArtworkRefresh() }))
        let cast = Self.makeTemplate(tab: .cast,
                                     sections: CarPlayTemplates.castSections(state: currentCastState(),
                                                                           owner: self,
                                                                           prefersVideo: Self.isEntitledToVideo))
        let browser = Self.makeTemplate(tab: .browser,
                                        sections: CarPlayTemplates.browserSections(currentURL: BrowserTabManager.shared.activeTabURL,
                                                                                owner: self))

        home.leadingNavigationBarButtons = [
            CPBarButton(title: "Search", handler: { [weak self] _ in self?.presentSearch() })
        ]
        home.emptyViewTitleVariants = ["No channels"]
        home.emptyViewSubtitleVariants = ["Add a playlist source in the DrivePlay app"]
        favorites.emptyViewTitleVariants = ["No favorites yet"]
        favorites.emptyViewSubtitleVariants = ["Add a favorite on the phone — it appears here at once"]

        self.homeTemplate = home
        self.favoritesTemplate = favorites
        self.castTemplate = cast
        self.browserTemplate = browser

        let bar = CPTabBarTemplate(templates: [home, favorites, cast, browser])
        bar.delegate = self
        tabBarTemplate = bar

        interfaceController.setRootTemplate(bar, animated: false) { success, error in
            if !success {
                NSLog("DRIVEPLAY setRootTemplate failed: %@", String(describing: error))
            }
        }

        observeState()

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
        cancellables.removeAll()
        artworkRefresh?.cancel()
        artworkRefresh = nil
        // Nobody is left to watch the stream.
        ScreenShareService.shared.stopRelay()
        interfaceController = nil
        carWindow = nil
        tabBarTemplate = nil
        homeTemplate = nil
        favoritesTemplate = nil
        castTemplate = nil
        browserTemplate = nil
        searchTemplate = nil
    }

    // MARK: - The tabs

    /// A tab's template — the title and the icon the tab bar shows.
    static func makeTemplate(tab: CarPlayTab, sections: [CPListSection]) -> CPListTemplate {
        let template = CPListTemplate(title: tab.rawValue, sections: sections)
        template.tabTitle = tab.rawValue
        template.tabImage = tab.image
        return template
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

        // The share has a state of its own.
        ScreenShareService.shared.$state
            .combineLatest(ScreenShareService.shared.$playlistURL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCast() }
            .store(in: &cancellables)

        // The browser shows what the phone shows.
        BrowserTabManager.shared.$activeTabURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshBrowser() }
            .store(in: &cancellables)
    }

    /// The catalogue and the favourites are one thing: they come from the same
    /// list, so both tabs are rebuilt together.
    private func refreshCatalogue() {
        let store = PlaylistStore.shared
        homeTemplate?.updateSections(CarPlayTemplates.homeSections(groups: store.allGroups,
                                                                   channels: store.channels,
                                                                   owner: self,
                                                                   prefersVideo: Self.isEntitledToVideo,
                                                                   onArtwork: { [weak self] in self?.scheduleArtworkRefresh() }))
        favoritesTemplate?.updateSections(CarPlayTemplates.favoritesSections(channels: store.favoriteChannels,
                                                                            owner: self,
                                                                            prefersVideo: Self.isEntitledToVideo,
                                                                            onArtwork: { [weak self] in self?.scheduleArtworkRefresh() }))
    }

    private func refreshCast() {
        castTemplate?.updateSections(CarPlayTemplates.castSections(state: currentCastState(),
                                                                  owner: self,
                                                                  prefersVideo: Self.isEntitledToVideo))
    }

    private func refreshBrowser() {
        browserTemplate?.updateSections(CarPlayTemplates.browserSections(currentURL: BrowserTabManager.shared.activeTabURL,
                                                                         owner: self))
    }

    /// The state the Cast tab shows — read from the app, not guessed.
    private func currentCastState() -> CarPlayCastState {
        let playback = PlaybackManager.shared
        let share = ScreenShareService.shared
        return CarPlayCastState(
            pictureOnCar: playback.isPlayingOnCar,
            isPlaying: playback.isPlaying,
            share: share.state,
            shareURL: share.networkPlaylistURL?.absoluteString ?? share.playlistURL?.absoluteString
        )
    }

    /// The logos arrive one at a time — the screen is rebuilt once they settled.
    private func scheduleArtworkRefresh() {
        artworkRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshCatalogue() }
        artworkRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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

    func presentSearch() {
        guard let interfaceController else { return }
        let template = searchTemplate ?? CPSearchTemplate()
        template.delegate = self
        searchTemplate = template
        interfaceController.presentTemplate(template, animated: true) { success, error in
            if !success {
                NSLog("DRIVEPLAY present search failed: %@", String(describing: error))
            }
        }
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
        ScreenShareService.shared.stopRelay()
        refreshCast()
    }

    /// Opens a site in the app's own browser **on the phone** — the car cannot
    /// show a page of its own, but the phone's shared screen can.
    func openOnPhone(url: String) {
        guard !url.isEmpty else { return }
        BrowserTabManager.shared.loadURLInActiveTab(url)
        // The relay waits for the broadcast the user starts from the Control Center.
        ScreenShareService.shared.startRelay()
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

        completionHandler(filtered.prefix(30).map { channel in
            CarPlayTemplates.channelItem(channel, owner: self, prefersVideo: Self.isEntitledToVideo)
        })
    }

    public func searchTemplate(_ searchTemplate: CPSearchTemplate,
                               selectedResult item: CPListItem,
                               completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
