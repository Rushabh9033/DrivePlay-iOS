import XCTest
import CarPlay
@testable import CarTV

/// Covers the structure of the car's templates.
///
/// CarPlay's `CPInterfaceController` can only be created by a connected scene, so the
/// templates that the scene delegate builds are the testable part of the car UI.
final class CarPlayTemplateTests: XCTestCase {

    private func channel(_ name: String, group: String) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                groupTitle: group)
    }

    private func items(in section: CPListSection) -> [CPListItem] {
        section.items.compactMap { $0 as? CPListItem }
    }

    /// The channel names a section carries — the car shows them as rows on the
    /// older systems and as cards on the ones that know them.
    private func channelNames(in section: CPListSection) -> [String] {
        var names: [String] = []
        for item in section.items {
            if #available(iOS 26.0, *), let row = item as? CPListImageRowItem {
                names.append(contentsOf: row.elements
                    .compactMap { ($0 as? CPListImageRowItemCardElement)?.title })
            }
        }
        names.append(contentsOf: items(in: section)
            .compactMap { $0.text }
            .filter { !$0.hasPrefix("Show all") })
        return names
    }

    /// AC1: the car lists every channel of the playlist under "All", then the
    /// categories — each with the count it really has.
    func test_AC1_the_car_lists_every_channel_under_all_and_then_the_categories() {
        let groups = [
            ChannelGroup(name: "Movies", channels: [channel("A", group: "Movies"), channel("B", group: "Movies")]),
            ChannelGroup(name: "News", channels: [channel("C", group: "News")])
        ]
        let all = groups.flatMap(\.channels)

        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: all,
                                                    owner: nil,
                                                    prefersVideo: false)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].header, "All")
        XCTAssertEqual(sections[0].headerSubtitle, "3 channels")
        XCTAssertEqual(channelNames(in: sections[0]), ["A", "B", "C"])
        XCTAssertEqual(sections[1].header, "Movies")
        XCTAssertEqual(sections[1].headerSubtitle, "2 channels")
        XCTAssertEqual(sections[2].header, "News")
        XCTAssertEqual(sections[2].headerSubtitle, "1 channels")
    }

    /// AC2: with nothing loaded the car says so instead of showing an empty list.
    func test_AC2_root_template_shows_an_empty_state() {
        let sections = CarPlayTemplates.homeSections(groups: [], channels: [], owner: nil, prefersVideo: false)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(items(in: sections[0]).map(\.text), ["No channels"])
    }

    /// AC3: a category that holds no channels is not listed.
    func test_AC3_empty_groups_are_not_listed() {
        let groups = [
            ChannelGroup(name: "Empty", channels: []),
            ChannelGroup(name: "Movies", channels: [channel("A", group: "Movies")])
        ]

        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: groups.flatMap(\.channels),
                                                    owner: nil,
                                                    prefersVideo: false)

        XCTAssertEqual(sections.map(\.header), ["All", "Movies"])
    }

    /// AC4: the channel picker is a list of channel rows, not a grid — only `CPListItem`
    /// carries a `playbackConfiguration`, which is how CarPlay is told a selection is video.
    func test_AC4_channel_picker_is_a_list_of_channel_rows() {
        let group = ChannelGroup(name: "Movies", channels: [
            channel("A", group: "Movies"),
            channel("B", group: "Movies")
        ])

        let template = CarPlaySceneDelegate.makeChannelTemplate(group: group, owner: nil)

        XCTAssertEqual(template.title, "Movies")
        XCTAssertEqual(template.sections.count, 1)
        XCTAssertEqual(items(in: template.sections[0]).map(\.text), ["A", "B"])
    }

    /// AC5: on iOS 26.4+ a channel row asks CarPlay for the video surface — but
    /// only when this build carries the video entitlement. Asking for it without
    /// the entitlement makes the system refuse the playback ("presentation is
    /// video but app does not have the video entitlement"), so a build that is
    /// signed for the audio category asks for the now-playing screen instead.
    func test_AC5_channel_rows_request_video_presentation_only_when_entitled() {
        guard #available(iOS 26.4, *) else { return }

        let group = ChannelGroup(name: "Live", channels: [channel("A", group: "Live")])

        let entitled = CarPlaySceneDelegate.makeChannelTemplate(group: group, owner: nil, prefersVideo: true)
        let entitledRow = items(in: entitled.sections[0])[0]
        XCTAssertEqual(entitledRow.playbackConfiguration?.preferredPresentation, .video)
        XCTAssertEqual(entitledRow.playbackConfiguration?.playbackAction, .play)

        let audio = CarPlaySceneDelegate.makeChannelTemplate(group: group, owner: nil, prefersVideo: false)
        let audioRow = items(in: audio.sections[0])[0]
        XCTAssertEqual(audioRow.playbackConfiguration?.preferredPresentation, .audio)
        XCTAssertEqual(audioRow.playbackConfiguration?.playbackAction, .play)
    }

    /// AC33: the screen-share row is a list row that asks CarPlay for the video surface.
    ///
    /// The share used to be a bar button, and a bar button carries no
    /// `playbackConfiguration` — so CarPlay had nothing to tell it that the content
    /// behind the selection is video, and the car's screen had no picture to draw.
    func test_AC33_the_screen_share_row_asks_for_the_video_surface() {
        guard #available(iOS 26.4, *) else { return }

        let sections = CarPlayTemplates.castSections(state: CarPlayCastState(), owner: nil, prefersVideo: true)
        let row = sections.flatMap { items(in: $0) }
            .first { $0.text == "Mirror this phone's screen" }

        XCTAssertNotNil(row)
        XCTAssertEqual(row?.playbackConfiguration?.preferredPresentation, .video)
        XCTAssertEqual(row?.playbackConfiguration?.playbackAction, .play)
    }

    /// AC36: the app asks for the video surface exactly when it is entitled to it.
    ///
    /// The entitlement is Apple-granted and lives on the app id, so the build is
    /// either signed with it or it does not build at all. The build says which,
    /// through the Info.plist — and the Info.plist value comes from the same
    /// setting as the entitlements file, so the two cannot drift apart.
    func test_AC36_the_app_asks_for_video_only_when_the_build_carries_the_entitlement() {
        guard #available(iOS 26.4, *) else { return }

        XCTAssertEqual(CarPlaySceneDelegate.playbackConfiguration(prefersVideo: true).preferredPresentation, .video)
        XCTAssertEqual(CarPlaySceneDelegate.playbackConfiguration(prefersVideo: false).preferredPresentation, .audio)
        XCTAssertEqual(
            CarPlaySceneDelegate.isEntitledToVideo,
            (Bundle.main.object(forInfoDictionaryKey: "CarPlayCategory") as? String) == "video",
            "the app has to believe what it was signed with"
        )
    }
}

/// The car's four tabs and what they show.
@MainActor
final class CarPlayTabTests: XCTestCase {

    /// Records what a row asked the app to do.
    private final class SpyActions: CarPlayTabActions {
        var played: [String] = []
        var pushed: [(title: String, channels: [Channel])] = []
        var opened: [String] = []
        var pictureToggled = false
        var playbackToggled = false
        var shareStarted = false
        var shareStopped = false

        func play(channel: Channel) { played.append(channel.name) }
        func pushChannels(title: String, channels: [Channel]) { pushed.append((title, channels)) }
        func presentSearch() {}
        func togglePicture() { pictureToggled = true }
        func togglePlayback() { playbackToggled = true }
        func startScreenShare() { shareStarted = true }
        func stopScreenShare() { shareStopped = true }
        func openOnPhone(url: String) { opened.append(url) }
    }

    private func channel(_ name: String, group: String) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                groupTitle: group)
    }

    private func items(in section: CPListSection) -> [CPListItem] {
        section.items.compactMap { $0 as? CPListItem }
    }

    /// Taps a channel on the car — a card on the systems that know them, a row
    /// on the older ones.
    @discardableResult
    private func tap(channel name: String, in section: CPListSection, spy: SpyActions) -> Bool {
        for item in section.items {
            if let row = item as? CPListItem, row.text == name {
                row.handler?(row, {})
                return true
            }
            if #available(iOS 26.0, *), let imageRow = item as? CPListImageRowItem {
                let titles = imageRow.elements
                    .compactMap { ($0 as? CPListImageRowItemCardElement)?.title }
                if let index = titles.firstIndex(of: name) {
                    imageRow.listImageRowHandler?(imageRow, index, {})
                    return true
                }
            }
        }
        return false
    }

    /// AC55: the car's screen is a tab bar with the tabs Home, Favorites, Cast
    /// and Browser — every one of them carries its own title and icon.
    func test_AC55_the_car_screen_is_a_tab_bar_with_four_tabs() {
        XCTAssertEqual(CarPlayTab.allCases.map(\.rawValue), ["Home", "Favorites", "Cast", "Browser"])

        for tab in CarPlayTab.allCases {
            let template = CarPlaySceneDelegate.makeTemplate(tab: tab, sections: [])
            XCTAssertEqual(template.tabTitle, tab.rawValue)
            XCTAssertNotNil(template.tabImage, "the tab \(tab.rawValue) has no icon")
        }
    }

    /// AC56: the Home tab shows the whole playlist under "All" — with the count
    /// the playlist really has.
    func test_AC56_the_home_tab_shows_the_whole_playlist_under_all() {
        let channels = (1...40).map { channel("Channel \($0)", group: "Sports") }

        let sections = CarPlayTemplates.homeSections(groups: [], channels: channels, owner: nil, prefersVideo: false)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].header, "All")
        XCTAssertEqual(sections[0].headerSubtitle, "40 channels")
    }

    /// AC57: every category shows its own title, the count it really has and its
    /// own artwork.
    func test_AC57_every_category_shows_its_title_its_count_and_its_artwork() {
        let groups = [
            ChannelGroup(name: "Movies", channels: [channel("A", group: "Movies")]),
            ChannelGroup(name: "News", channels: [channel("B", group: "News")])
        ]

        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: groups.flatMap(\.channels),
                                                    owner: nil,
                                                    prefersVideo: false)

        XCTAssertEqual(sections.map(\.header), ["All", "Movies", "News"])
        XCTAssertEqual(sections.map(\.headerSubtitle), ["2 channels", "1 channels", "1 channels"])
        XCTAssertNotNil(sections[1].headerImage, "a category without artwork")
        XCTAssertNotNil(sections[2].headerImage, "a category without artwork")
    }

    /// AC58: every category has a way into all of its entries — and it leads to
    /// the whole category, not to the few cards on the screen.
    func test_AC58_every_category_has_a_way_into_all_of_its_entries() {
        let spy = SpyActions()
        let many = (1...12).map { channel("M\($0)", group: "Movies") }
        let groups = [ChannelGroup(name: "Movies", channels: many)]

        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: many,
                                                    owner: spy,
                                                    prefersVideo: false)
        let showAll = items(in: sections[1]).first { $0.text?.hasPrefix("Show all") == true }

        XCTAssertNotNil(showAll)
        showAll?.handler?(showAll!, {})
        XCTAssertEqual(spy.pushed.count, 1)
        XCTAssertEqual(spy.pushed.first?.title, "Movies")
        XCTAssertEqual(spy.pushed.first?.channels.count, 12)
    }

    /// AC59: the Favorites tab shows the favourites the phone holds — the same
    /// list, with its count.
    func test_AC59_the_favorites_tab_shows_the_favorites_of_the_phone() {
        let spy = SpyActions()
        let favorites = [channel("Sky Sports", group: "Sports"), channel("CNN", group: "News")]

        let sections = CarPlayTemplates.favoritesSections(channels: favorites, owner: spy, prefersVideo: false)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].headerSubtitle, "2 channels")

        XCTAssertTrue(tap(channel: "Sky Sports", in: sections[0], spy: spy))
        XCTAssertEqual(spy.played, ["Sky Sports"])
    }

    /// AC60: the Cast tab shows where the picture is and what the share does.
    func test_AC60_the_cast_tab_shows_where_the_picture_is_and_what_the_share_does() {
        let spy = SpyActions()
        var state = CarPlayCastState()
        state.pictureOnCar = true
        state.isPlaying = true
        state.share = .sharing
        state.shareURL = "http://127.0.0.1:47311/abc/live.m3u8"

        let sections = CarPlayTemplates.castSections(state: state, owner: spy, prefersVideo: false)
        let rows = sections.flatMap { items(in: $0) }

        XCTAssertEqual(rows.first { $0.text == "Picture on the car" }?.detailText,
                       "Tap to bring it back to the phone")
        XCTAssertEqual(rows.first { $0.text == "Pause" }?.detailText,
                       "The stream stays on the car")
        XCTAssertEqual(rows.first { $0.text == "Mirror this phone's screen" }?.detailText,
                       "Sharing http://127.0.0.1:47311/abc/live.m3u8")

        rows.first { $0.text == "Picture on the car" }?.handler?(rows[0], {})
        rows.first { $0.text == "Pause" }?.handler?(rows[1], {})
        rows.first { $0.text == "Mirror this phone's screen" }?.handler?(rows[2], {})
        rows.first { $0.text == "Stop mirroring" }?.handler?(rows[3], {})
        XCTAssertTrue(spy.pictureToggled)
        XCTAssertTrue(spy.playbackToggled)
        XCTAssertTrue(spy.shareStarted)
        XCTAssertTrue(spy.shareStopped)
    }

    /// AC61: the Browser tab offers the sites of the app's own browser — the
    /// same catalogue the phone shows — and opens them on the phone, because
    /// CarPlay has no web view of its own.
    func test_AC61_the_browser_tab_offers_the_sites_of_the_apps_own_browser() {
        let spy = SpyActions()

        let sections = CarPlayTemplates.browserSections(currentURL: "https://example.com/watch", owner: spy)
        let rows = sections.flatMap { items(in: $0) }

        XCTAssertEqual(rows.first { $0.text == "On the phone now" }?.detailText, "https://example.com/watch")

        let youtube = rows.first { $0.text == "YouTube" }
        XCTAssertNotNil(youtube, "the car's browser has to offer the phone's sites")
        youtube?.handler?(youtube!, {})
        XCTAssertEqual(spy.opened, ["https://m.youtube.com"])

        // The catalogue is the app's own — the phone's browser shows the same.
        XCTAssertEqual(BrowserCatalog.videoAndMusic.first?.name, "YouTube")
        XCTAssertTrue(BrowserCatalog.groups.contains { $0.title == "Live & Sports" })
    }
}

/// The artwork the car shows.
@MainActor
final class CarPlayArtworkTests: XCTestCase {

    private func channel(_ name: String, logo: String? = nil) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/a.m3u8")!,
                groupTitle: "Sports",
                logoURL: logo.flatMap { URL(string: $0) })
    }

    /// AC62: a logo is drawn at its own aspect ratio — never stretched, never
    /// clipped out of the card.
    func test_AC62_a_logo_is_drawn_at_its_own_aspect_ratio() {
        let card = CGRect(x: 0, y: 0, width: 100, height: 100)
        let wide = CarPlayArtwork.logoRect(logoSize: CGSize(width: 200, height: 50), in: card)

        XCTAssertEqual(wide.width / wide.height, 4, accuracy: 0.01)
        XCTAssertTrue(card.contains(wide), "the logo has to stay inside the card")
        XCTAssertTrue(card.contains(CarPlayArtwork.logoRect(logoSize: CGSize(width: 50, height: 200), in: card)))
    }

    /// AC63: a logo is fetched once, however often the screen is rebuilt.
    func test_AC63_a_logo_is_fetched_once_however_often_the_screen_is_rebuilt() {
        let artwork = CarPlayArtwork()
        var fetches = 0
        artwork.fetchLogo = { _, completion in
            fetches += 1
            completion(UIImage())
        }
        let subject = channel("Sky Sports", logo: "https://example.com/sky.png")

        let done = expectation(description: "the logo arrived")
        artwork.fetchTile(for: subject) { done.fulfill() }
        wait(for: [done], timeout: 2)

        // The screen is rebuilt — the logo is already there.
        var refetched = false
        artwork.fetchTile(for: subject) { refetched = true }
        XCTAssertFalse(refetched)
        XCTAssertEqual(fetches, 1)
    }

    /// AC65: the artwork is drawn for the **car's** screen, not for the phone's.
    ///
    /// Apple says it plainly: *"images you display in any template should be
    /// sized to a display scale matching the scale of the `carTraitCollection`,
    /// not the scale of the iOS device's main screen."* A tile drawn for the
    /// phone is soft on the car.
    func test_AC65_the_artwork_is_drawn_at_the_cars_scale() {
        let artwork = CarPlayArtwork()
        let phoneScale = CarPlayArtwork.displayScale
        defer { CarPlayArtwork.displayScale = phoneScale }
        CarPlayArtwork.displayScale = 2

        let tile = artwork.tile(for: channel("Sky Sports"), size: CGSize(width: 60, height: 60))

        XCTAssertEqual(tile.size, CGSize(width: 60, height: 60), "the card keeps its size in points")
        XCTAssertEqual(tile.scale, 2, "the pixels have to be the car's pixels")
    }

    /// AC66: a rebuilt screen does not draw every card again.
    ///
    /// The screen is rebuilt whenever a favourite is toggled or a logo arrives;
    /// with thousands of channels, drawing every card again is a stall.
    func test_AC66_a_rebuilt_screen_does_not_draw_the_cards_again() {
        let artwork = CarPlayArtwork()
        let subject = channel("Sky Sports", logo: "https://example.com/sky.png")

        let first = artwork.tile(for: subject, size: CGSize(width: 60, height: 60))
        let second = artwork.tile(for: subject, size: CGSize(width: 60, height: 60))

        XCTAssertTrue(first === second, "the card has to be drawn once")
    }
}

/// The car's template calls must never take the app down.
///
/// CarPlay **throws an `NSException` when a template call fails and no completion
/// handler was given**, and an uncaught ObjC exception aborts the process. That is
/// what killed the app on every row tap: the now-playing template was presented
/// modally — `presentTemplate` accepts only action sheets, alerts and voice
/// control, so the presentation failed — and the failure with no completion
/// handler was fatal.
///
/// The now-playing screen is the system's to present: the rows carry a
/// `playbackConfiguration`, and CarPlay shows the media presentation itself when
/// the item is selected. The app only configures the shared template.
@MainActor
final class CarPlayPresentationTests: XCTestCase {

    private var delegateSource: URL {
        RepositoryFixture.root.appendingPathComponent("CarTV/Sources/App/CarPlaySceneDelegate.swift")
    }

    /// AC45: tapping a row on the car never kills the app.
    func test_AC45_a_failed_template_call_is_reported_and_never_thrown() throws {
        try RepositoryFixture.skipUnlessPresent()
        let text = try String(contentsOf: delegateSource, encoding: .utf8)

        XCTAssertFalse(text.contains("presentTemplate(nowPlaying"),
                       "the now-playing template must not be presented modally")
        XCTAssertFalse(text.contains("presentTemplate(CPNowPlayingTemplate"),
                       "the now-playing template must not be presented modally")
        XCTAssertFalse(text.contains("completion: nil"),
                       "every CarPlay template call must carry a completion handler, " +
                       "or a failed call throws an NSException that kills the app")

        // What the app still does: configure the shared template, which is the
        // instance the system presents.
        CarPlaySceneDelegate.prepareNowPlaying()
        XCTAssertTrue(CPNowPlayingTemplate.shared.nowPlayingButtons.isEmpty)
    }
}

/// The handset search box must not shrink the catalogue on the car screen.
@MainActor
final class CarPlayCatalogueIsolationTests: XCTestCase {

    /// AC6: `allGroups` is the unfiltered index, `groups` follows the handset search box.
    func test_AC6_allGroups_ignores_the_handset_search_query() {
        let store = PlaylistStore.shared
        let originalChannels = store.channels
        let originalQuery = store.searchQuery
        defer {
            store.channels = originalChannels
            store.searchQuery = originalQuery
            store.rebuildIndex()
        }

        store.channels = [
            Channel(name: "Match", streamURL: URL(string: "https://example.com/a.m3u8")!, groupTitle: "Sports"),
            Channel(name: "Headlines", streamURL: URL(string: "https://example.com/b.m3u8")!, groupTitle: "News")
        ]
        store.rebuildIndex()
        store.searchQuery = "sports"

        XCTAssertEqual(store.groups.map(\.name), ["Sports"])
        XCTAssertEqual(store.allGroups.map(\.name).sorted(), ["News", "Sports"])
    }
}
