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
        var pushedCategories: [(title: String, categories: [ChannelGroup])] = []
        var pictureToggled = false
        var playbackToggled = false
        var shareStarted = false
        var shareStopped = false
        var addressBarPushed = false
        var opened: [String] = []

        func play(channel: Channel) { played.append(channel.name) }
        func pushChannels(title: String, channels: [Channel]) { pushed.append((title, channels)) }
        func pushCategories(title: String, categories: [ChannelGroup]) { pushedCategories.append((title, categories)) }
        func pushChannelSearch() {}
        func togglePicture() { pictureToggled = true }
        func togglePlayback() { playbackToggled = true }
        func startScreenShare() { shareStarted = true }
        func stopScreenShare() { shareStopped = true }
        func pushBrowserAddressBar() { addressBarPushed = true }
        func openOnPhone(address: String) { opened.append(address) }
    }

    private func channel(_ name: String, group: String, logo: String? = nil) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                groupTitle: group,
                logoURL: logo.flatMap { URL(string: $0) })
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

    /// AC92: the categories the Home tab has no room for are still on the car.
    ///
    /// The Home tab shows a handful of categories, because every category is a
    /// row of cards and every card is a picture — fifty of them took the
    /// CarPlay session down. The rest are not lost: "All categories" opens
    /// every one of them, with the count it really has.
    func test_AC92_the_categories_the_home_tab_has_no_room_for_are_still_on_the_car() {
        let spy = SpyActions()
        let groups = (1...30).map { index in
            ChannelGroup(name: "Group \(index)", channels: [channel("C\(index)", group: "Group \(index)")])
        }
        let channels = groups.flatMap(\.channels)

        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: channels,
                                                    owner: spy,
                                                    prefersVideo: false)

        // The Home tab is small enough to be drawn.
        XCTAssertLessThanOrEqual(sections.count, CarPlayTemplates.homeCategoryLimit + 1)

        // And the categories it left out are still there.
        let allCategories = items(in: sections[0]).first { $0.text?.hasPrefix("All categories") == true }
        XCTAssertNotNil(allCategories, "the car has no way into the other categories")
        allCategories?.handler?(allCategories!, {})
        XCTAssertEqual(spy.pushedCategories.count, 1)
        XCTAssertEqual(spy.pushedCategories.first?.categories.count, 30)
    }

    /// AC93: the category list shows every category with its real count, and
    /// opens the channels of the one that is tapped.
    func test_AC93_the_category_list_shows_every_category_with_its_real_count() {
        let spy = SpyActions()
        let groups = [
            ChannelGroup(name: "Movies", channels: (1...3).map { channel("M\($0)", group: "Movies") }),
            ChannelGroup(name: "News", channels: [channel("N", group: "News")])
        ]

        let template = CarPlayTemplates.categoryList(title: "Categories", categories: groups, owner: spy)
        let rows = items(in: template.sections[0])

        XCTAssertEqual(rows.map(\.text), ["Movies", "News"])
        XCTAssertEqual(rows.map(\.detailText), ["3 channels", "1 channels"])

        rows[0].handler?(rows[0], {})
        XCTAssertEqual(spy.pushed.count, 1)
        XCTAssertEqual(spy.pushed.first?.title, "Movies")
        XCTAssertEqual(spy.pushed.first?.channels.count, 3)
    }

    /// AC94: a logo that arrives patches the card that shows it — the
    /// template is not rebuilt.
    ///
    /// A rebuild per logo sent the whole catalogue to the car again and
    /// again: with a few hundred cards that is what took the CarPlay session
    /// down. The card is told, and that is all.
    func test_AC94_a_logo_that_arrives_patches_the_card_and_does_not_rebuild_the_screen() {
        guard #available(iOS 26.0, *) else { return }

        let artwork = CarPlayArtwork.shared
        let original = artwork.fetchLogo
        defer { artwork.fetchLogo = original }

        var fetched = 0
        artwork.fetchLogo = { _, completion in
            fetched += 1
            completion(UIImage())
        }

        let sections = CarPlayTemplates.homeSections(groups: [],
                                                    channels: [channel("Sky Sports",
                                                                        group: "Sports",
                                                                        logo: "https://example.com/sky.png")],
                                                    owner: nil,
                                                    prefersVideo: false)

        guard #available(iOS 26.0, *),
              let row = sections.first?.items.compactMap({ $0 as? CPListImageRowItem }).first,
              let element = row.elements.first else {
            XCTFail("the card row is missing")
            return
        }
        let before = element.image

        // The logo arrives.
        let settled = expectation(description: "the logo arrived")
        artwork.loadLogo(for: channel("Sky Sports",
                                      group: "Sports",
                                      logo: "https://example.com/sky.png")) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 2)

        // The screen is the same screen — the card was told, not replaced.
        XCTAssertTrue(row.elements.first === element, "the card has to be the same card")
        XCTAssertEqual(fetched, 1)
        XCTAssertNotNil(before)
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
        // There is a player: the picture is on the car and it is playing.
        state.hasPlayer = true
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

        // The rows are looked up, not counted: a row that is missing has to
        // fail the assertion, not take the whole test runner down with it.
        for text in ["Picture on the car", "Pause", "Mirror this phone's screen", "Stop mirroring"] {
            guard let row = rows.first(where: { $0.text == text }) else {
                XCTFail("the Cast tab has no row titled \(text)")
                continue
            }
            row.handler?(row, {})
        }
        XCTAssertTrue(spy.pictureToggled)
        XCTAssertTrue(spy.playbackToggled)
        XCTAssertTrue(spy.shareStarted)
        XCTAssertTrue(spy.shareStopped)
    }

    /// AC61: the Browser tab offers the sites of the app's own browser — the
    /// same catalogue the phone shows — and opens them on the phone, because
    /// CarPlay has no web view of its own.
    func test_AC61_the_browser_tab_offers_the_sites_of_the_apps_own_browser() {
        let browser = CarPlayBrowserSearch()

        var results: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "") { results = $0 }

        let youtube = results.first { $0.text == "YouTube" }
        XCTAssertNotNil(youtube, "the car's browser has to offer the phone's sites")

        // The catalogue is the app's own — the phone's browser shows the same.
        XCTAssertEqual(BrowserCatalog.videoAndMusic.first?.name, "YouTube")
        XCTAssertTrue(BrowserCatalog.groups.contains { $0.title == "Live & Sports" })
    }

    /// AC99: the Browser tab's header is a **search bar** — the address bar of
    /// the car's browser — and what the user types goes to the phone's own
    /// browser, which turns a URL into a URL and anything else into a search.
    func test_AC99_the_browsers_header_is_a_search_bar_that_redirects_to_the_phone() {
        let browser = CarPlayBrowserSearch()
        var opened: [String] = []
        browser.openAddress = { opened.append($0) }

        var results: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "sky sports") { results = $0 }
        // The row is looked up **by its text**, never by its position: the
        // search's own list carries the way back as its first row.
        guard let row = results.first(where: { $0.text == "Open \"sky sports\"" }) else {
            XCTFail("the browser's search bar found nothing")
            return
        }

        browser.searchTemplate(CPSearchTemplate(), selectedResult: row) {}

        XCTAssertEqual(opened, ["sky sports"],
                       "what the user typed goes straight to the phone's browser")

        // The phone's browser's own rule — the same one the car uses.
        XCTAssertEqual(BrowserTabItem.destination(for: "example.com"), "https://example.com")
        XCTAssertEqual(BrowserTabItem.destination(for: "sky sports"),
                       "https://www.google.com/search?q=sky%20sports")
    }

    /// AC100: a site of the browser opens on the phone — the car has no web
    /// view of its own, so the page is opened in the app's own browser.
    func test_AC100_a_site_row_opens_on_the_phone() {
        let browser = CarPlayBrowserSearch()
        var opened: [String] = []
        browser.openAddress = { opened.append($0) }

        var results: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "") { results = $0 }
        guard let youtube = results.first(where: { $0.text == "YouTube" }) else {
            XCTFail("the browser has no YouTube row")
            return
        }

        browser.searchTemplate(CPSearchTemplate(), selectedResult: youtube) {}

        XCTAssertEqual(opened, ["https://m.youtube.com"])
    }

    /// AC101: the Browser tab is a **list** — the way into the address bar,
    /// the page the phone shows now, and the app's own sites.
    ///
    /// The tab bar rejects a search template (`-validateTemplates:` raises and
    /// the app dies at every scene connect), so the tab is a list and the
    /// address bar is pushed onto the stack.
    func test_AC101_the_browser_tab_is_a_list_with_the_address_bar_and_the_sites() {
        let spy = SpyActions()

        let sections = CarPlayTemplates.browserSections(currentURL: "https://example.com/watch",
                                                         owner: spy)

        let top = items(in: sections[0]).map(\.text)
        XCTAssertEqual(top, ["Search or type a URL", "On the phone now"],
                       "the Browser tab opens with the address bar and the page the phone shows")

        // The address bar is pushed — it is never a tab.
        let addressBar = items(in: sections[0])[0]
        addressBar.handler?(addressBar, {})
        XCTAssertTrue(spy.addressBarPushed, "the address bar was not pushed onto the stack")

        // A site of the app's own browser opens on the phone.
        let all = sections.flatMap { items(in: $0) }
        guard let youtube = all.first(where: { $0.text == "YouTube" }) else {
            XCTFail("the browser has no YouTube row")
            return
        }
        youtube.handler?(youtube, {})
        XCTAssertEqual(spy.opened, ["https://m.youtube.com"])
    }

    /// AC102: the tab bar is built from **lists** only.
    ///
    /// A search template inside a tab bar is what killed the app; the tab bar
    /// takes lists, and the compiler is what keeps it that way.
    func test_AC102_the_tab_bar_is_built_from_lists_only() {
        let bar = CarPlaySceneDelegate.makeTabBar(CarPlayTab.allCases.map {
            CarPlaySceneDelegate.makeTemplate(tab: $0, sections: [])
        })

        XCTAssertEqual(bar.templates.count, 4)
        for template in bar.templates {
            XCTAssertTrue(template is CPListTemplate,
                          "a tab that is not a list takes the app down")
        }
    }
}

/// The switch between the phone and the car's display.
@MainActor
final class CarOutputSwitchTests: XCTestCase {

    /// AC98: with a car connected "Play on Car Display" goes **straight to the
    /// car** — the system's list of displays is never shown. Without a car the
    /// list is the only way to reach a display, so it is shown then.
    func test_AC98_play_on_car_display_goes_straight_to_the_car() {
        let playback = PlaybackManager.shared
        defer { playback.isCarConnected = false }

        playback.isCarConnected = false
        XCTAssertTrue(playback.needsRoutePicker,
                      "without a car there is nowhere to go, so the list of displays is the way")
        XCTAssertFalse(playback.playOnCarDisplay())

        playback.isCarConnected = true
        XCTAssertFalse(playback.needsRoutePicker,
                       "with a car connected the list of displays must not be shown")
        XCTAssertTrue(playback.playOnCarDisplay(),
                      "with a car connected the picture goes there at once")
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
        artwork.loadLogo(for: subject) { _ in done.fulfill() }
        wait(for: [done], timeout: 2)

        // The screen is rebuilt — the logo is already there, so nothing is
        // downloaded a second time.
        artwork.loadLogo(for: subject) { _ in }
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

    /// AC95: the card that shows a logo is drawn from **that logo**.
    ///
    /// The logo cache is bounded and it throws the oldest pictures away, so a
    /// card drawn from a *lookup* can come back with the initials for a logo
    /// that was handed over a moment ago — and the car shows the initials for
    /// ever, because the card never changes again.
    func test_AC95_the_card_is_drawn_from_the_logo_that_arrived() {
        let artwork = CarPlayArtwork()
        let logo = CarPlayArtwork.draw(text: "L", color: .red, background: .red,
                                       size: CGSize(width: 20, height: 20))

        let tile = artwork.tile(for: channel("Sky Sports", logo: "https://example.com/sky.png"),
                                logo: logo,
                                size: CGSize(width: 60, height: 60))

        let pixel = centrePixel(of: tile)
        XCTAssertNotNil(pixel, "the card could not be read")
        XCTAssertGreaterThan(pixel?.red ?? 0, 200, "the card has to show the logo")
        XCTAssertLessThan(pixel?.green ?? 255, 80, "the card has to show the logo")
    }

    /// AC96: a logo the server refuses is asked for again.
    ///
    /// The playlist's logos come from a few CDNs, and the biggest of them
    /// (imgur) answers **429** when the phone asks for more than a hundred
    /// pictures in a short while — and the car asks for a whole category at
    /// once. A refused picture that is never asked for again leaves the car
    /// showing the initials.
    func test_AC96_a_logo_the_server_refuses_is_asked_for_again() {
        let artwork = CarPlayArtwork()
        var attempts = 0
        artwork.fetchLogo = { _, completion in
            attempts += 1
            completion(attempts < 2 ? nil : UIImage())
        }

        let arrived = expectation(description: "the logo arrived")
        artwork.loadLogo(for: channel("Sky Sports", logo: "https://example.com/sky.png")) { logo in
            XCTAssertNotNil(logo, "the logo was never taken")
            arrived.fulfill()
        }
        wait(for: [arrived], timeout: 15)

        XCTAssertEqual(attempts, 2, "the refused picture was not asked for again")
    }

    /// AC97: the car's cards carry no colour of our own.
    ///
    /// A tint on a card paints the frame around it **and** the text on it — in
    /// our green, on every card of every category. The car paints its own
    /// cards; the artwork carries the logo and nothing else.
    func test_AC97_the_cards_carry_no_colour_of_our_own() {
        // The artwork: the charcoal card, with nothing of ours painted on it.
        let tile = CarPlayArtwork.shared.tile(for: channel("Sky Sports"), size: CGSize(width: 60, height: 60))
        let ours = colours(of: tile).filter { $0.green > 150 && $0.red < 120 && $0.blue < 150 }
        XCTAssertTrue(ours.isEmpty, "the card carries a colour of ours: \(ours.prefix(3))")

        // The card element: the system's colour, not ours.
        guard #available(iOS 26.0, *) else { return }
        let channels = (1...8).map { channel("C\($0)") }
        let sections = CarPlayTemplates.homeSections(groups: [],
                                                     channels: channels,
                                                     owner: nil,
                                                     prefersVideo: false)
        let cards = sections.flatMap { section -> [CPListImageRowItemCardElement] in
            section.items.compactMap { item -> [CPListImageRowItemCardElement]? in
                guard let row = item as? CPListImageRowItem else { return nil }
                return row.elements.compactMap { $0 as? CPListImageRowItemCardElement }
            }.flatMap { $0 }
        }
        XCTAssertFalse(cards.isEmpty, "no card was built")
        for card in cards {
            XCTAssertNil(card.tintColor, "a card of ours paints the frame around the logo")
        }
    }

    /// The colour in the middle of a picture — the logo's own colour.
    private func centrePixel(of image: UIImage) -> (red: Int, green: Int, blue: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel,
                                      width: 1,
                                      height: 1,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The picture is drawn around the origin, so its middle lands on the
        // one pixel the context holds.
        context.draw(cgImage, in: CGRect(x: -CGFloat(cgImage.width) / 2,
                                          y: -CGFloat(cgImage.height) / 2,
                                          width: CGFloat(cgImage.width),
                                          height: CGFloat(cgImage.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    /// Every colour of a picture — so a colour of ours can be looked for.
    private func colours(of image: UIImage) -> [(red: Int, green: Int, blue: Int)] {
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]), Int(pixels[$0 + 1]), Int(pixels[$0 + 2]))
        }
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

/// The car's search has to play what it finds.
@MainActor
final class CarPlaySearchTests: XCTestCase {

    /// AC69: a result the user picks in the car's search plays the channel it
    /// stands for.
    ///
    /// A search result is **not** a list row. CarPlay hands the selection to
    /// `searchTemplate(_:selectedResult:completionHandler:)` and never calls
    /// the row's own handler — so a delegate that only answers the completion
    /// handler leaves the car with a search that finds channels and plays none
    /// of them.
    func test_AC69_a_selected_search_result_plays_the_channel_it_stands_for() {
        let store = PlaylistStore.shared
        let originalChannels = store.channels
        defer {
            store.channels = originalChannels
            store.rebuildIndex()
            PlaybackManager.shared.closePlayer()
        }

        // A file URL that is not there: the player fails to load it, which is
        // harmless — what matters is which channel was asked for.
        let missing = URL(fileURLWithPath: "/tmp/driveplay-no-such-stream.m3u8")
        let sky = Channel(name: "Sky Sports HD", streamURL: missing, groupTitle: "Sports")
        let news = Channel(name: "BBC News", streamURL: missing, groupTitle: "News")
        store.channels = [sky, news]
        store.rebuildIndex()

        let delegate = CarPlaySceneDelegate()
        var results: [CPListItem] = []
        delegate.searchTemplate(CPSearchTemplate(), updatedSearchText: "sky") { items in
            results = items
        }
        // The row is looked up **by its text**, never by its position: the
        // search's own list carries the way back as its first row.
        let row = results.first { $0.text == "Sky Sports HD" }
        XCTAssertNotNil(row, "the search did not find the channel")

        delegate.searchTemplate(CPSearchTemplate(), selectedResult: row!) {}

        XCTAssertEqual(PlaybackManager.shared.currentChannel?.id, sky.id,
                       "the selected search result did not play its channel")
    }

    /// AC141: the car's browser does not build its list again for every
    /// keystroke.
    ///
    /// The search template hands the car a fresh list on **every keystroke**,
    /// and every row carries a picture at the car's scale — so a list that is
    /// built again for every character is what took the CarPlay scene down.
    func test_AC141_the_cars_browser_does_not_build_its_list_again_for_every_keystroke() {
        let browser = CarPlayBrowserSearch()

        var first: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "") { first = $0 }
        var second: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "y") { second = $0 }

        let youtubeFirst = first.first { $0.text == "YouTube" }
        let youtubeSecond = second.first { $0.text == "YouTube" }
        XCTAssertNotNil(youtubeFirst, "the browser has no YouTube row")
        XCTAssertTrue(youtubeFirst === youtubeSecond,
                      "the row was built again, so its picture was drawn again")
    }

    /// AC153: the channel search does not build its rows again for every
    /// keystroke.
    ///
    /// `searchTemplate(_:updatedSearchText:completionHandler:)` is called on
    /// **every character**, and every row carries a picture at the car's
    /// scale — so a row that is built again is a picture that is drawn again.
    /// Thirty of those per keystroke is what took the CarPlay session down.
    func test_AC153_the_channel_search_does_not_build_its_rows_again_for_every_keystroke() {
        let store = PlaylistStore.shared
        let originalChannels = store.channels
        defer {
            store.channels = originalChannels
            store.rebuildIndex()
        }

        let missing = URL(fileURLWithPath: "/tmp/driveplay-no-such-stream.m3u8")
        let sky = Channel(name: "Sky Sports HD", streamURL: missing, groupTitle: "Sports")
        let news = Channel(name: "BBC News", streamURL: missing, groupTitle: "News")
        store.channels = [sky, news]
        store.rebuildIndex()

        let delegate = CarPlaySceneDelegate()
        var first: [CPListItem] = []
        delegate.searchTemplate(CPSearchTemplate(), updatedSearchText: "") { first = $0 }
        var second: [CPListItem] = []
        delegate.searchTemplate(CPSearchTemplate(), updatedSearchText: "s") { second = $0 }

        let skyFirst = first.first { $0.text == "Sky Sports HD" }
        let skySecond = second.first { $0.text == "Sky Sports HD" }
        XCTAssertNotNil(skyFirst, "the search did not offer the channel")
        XCTAssertNotNil(skySecond, "the search did not offer the channel for the typed text")
        XCTAssertTrue(skyFirst === skySecond,
                      "the row was built again, so its picture was drawn again")
    }

    /// AC154: the address bar has a way back to the list it was pushed from.
    ///
    /// A `CPSearchTemplate` does not conform to `CPBarButtonProviding` — it
    /// cannot carry a navigation bar button — so the way back has to be a row
    /// of the search's own list. Without one the car is stuck on the address
    /// bar for ever.
    func test_AC154_the_address_bar_has_a_way_back_to_the_sites() {
        let browser = CarPlayBrowserSearch()
        var opened: [String] = []
        browser.openAddress = { opened.append($0) }
        var dismissed = false
        browser.dismissAddressBar = { dismissed = true }

        var results: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "") { results = $0 }

        let back = results.first { $0.text == "Back to sites" }
        XCTAssertNotNil(back, "the address bar has no way back to the sites")

        // Typing must not take the way out away.
        var typed: [CPListItem] = []
        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "you") { typed = $0 }
        XCTAssertNotNil(typed.first { $0.text == "Back to sites" },
                        "the way back is gone while the user is typing")

        browser.searchTemplate(CPSearchTemplate(), selectedResult: back!) {}

        XCTAssertTrue(dismissed, "the way back did not take the car out of the address bar")
        XCTAssertTrue(opened.isEmpty, "the way back opened a page")
    }

    /// AC142: the phone is told that the car is waiting for the page.
    ///
    /// CarPlay has no web view of its own, so a page the user opens on the car
    /// runs on the phone and reaches the car through the phone's screen
    /// share — and iOS always asks the **user** to start a share, so the
    /// phone has to say that the car is waiting.
    func test_AC142_the_phone_is_told_that_the_car_is_waiting_for_the_page() {
        let share = ScreenShareService(relay: ScreenRelayListener(port: 47313))
        defer { share.stopRelay() }

        share.carRequestedPage("https://m.youtube.com")

        XCTAssertEqual(share.pendingCarPage, "https://m.youtube.com",
                       "the phone has to say that the car is waiting for the page")
        XCTAssertTrue(share.isWaitingForBroadcast,
                      "the relay has to be listening before the user picks the broadcast")
    }

    /// AC158: car navigation does not hijack the phone's selected tab.
    ///
    /// The car and phone have independent presentation states: CarPlay actions
    /// must not unexpectedly change the handset's active tab.
    func test_AC158_car_navigation_does_not_hijack_phone_tab() {
        let share = ScreenShareService(relay: ScreenRelayListener(port: 47414))
        defer { share.stopRelay() }

        let tabs = AppTabSelection.shared
        tabs.tab = .home

        share.carRequestedPage("https://m.youtube.com")

        XCTAssertEqual(tabs.tab, .home,
                       "the phone unexpectedly switched tabs — CarPlay must not alter handset UI presentation")
    }

    /// Verifies that pressing the keyboard's search button in CarPlay triggers the search.
    func test_keyboard_search_button_triggers_search() {
        let browser = CarPlayBrowserSearch()
        var opened: [String] = []
        browser.openAddress = { opened.append($0) }
        var dismissed = false
        browser.dismissAddressBar = { dismissed = true }

        browser.searchTemplate(CPSearchTemplate(), updatedSearchText: "https://google.com") { _ in }
        browser.searchTemplateSearchButtonPressed(CPSearchTemplate())

        XCTAssertEqual(opened, ["https://google.com"])
        XCTAssertTrue(dismissed)
    }

    /// Verifies that CarPlay browser interactions keep the phone's tab intact.
    func test_carplay_browser_interaction_preserves_handset_tab() {
        let tabs = AppTabSelection.shared
        tabs.tab = .settings

        let browser = CarPlayBrowserSearch()
        browser.openAddress("https://youtube.com")

        XCTAssertEqual(tabs.tab, .settings, "handset tab must remain unchanged during CarPlay browsing")
    }
}

/// How the car's screen behaves under load.
///
/// The car is a **slow** display: every picture and every row that changes is
/// carried over to it, and the CarPlay host watches how much work the app
/// asks of it — *"Updated resource consumption: 5.842s (58.97%)"* — and tears
/// the session down when it reaches a hundred per cent.
///
/// So the numbers here are not about the phone being quick. They are about
/// how much the **car** is asked to do.
final class CarPlayResponsivenessTests: XCTestCase {

    /// A playlist of the real shape: hundreds of channels in hundreds of
    /// categories.
    private func playlist(categories: Int = 184, perCategory: Int = 3) -> [ChannelGroup] {
        (0..<categories).map { index in
            ChannelGroup(name: "Category \(index)",
                         channels: (0..<perCategory).map { channel in
                             Channel(name: "Channel \(index)-\(channel)",
                                     streamURL: URL(string: "https://example.com/\(index)-\(channel).m3u8")!,
                                     groupTitle: "Category \(index)")
                         })
        }
    }

    /// AC104: the car's Home tab is built in a moment.
    ///
    /// The Home tab carries a card for every channel it shows, and every card
    /// is a picture the phone has to draw **for the car**. The whole screen
    /// is built when the scene connects, so the time it takes is the time the
    /// car shows **nothing**.
    func test_AC104_the_home_tab_is_built_in_a_moment() {
        let groups = playlist()
        let channels = groups.flatMap(\.channels)

        let started = Date()
        let sections = CarPlayTemplates.homeSections(groups: groups,
                                                    channels: channels,
                                                    owner: nil,
                                                    prefersVideo: false)
        let elapsed = Date().timeIntervalSince(started)

        // The screen the car gets.
        var cards = 0
        for section in sections {
            for item in section.items {
                if #available(iOS 26.0, *), let row = item as? CPListImageRowItem {
                    cards += row.elements.count
                }
            }
        }

        NSLog("DRIVEPLAY the Home tab: %d sections, %d cards, built in %.0f ms",
              sections.count, cards, elapsed * 1000)

        XCTAssertLessThan(elapsed, 1.0,
                          "building the Home tab took \(elapsed)s — the car waits that long for a screen")
    }

    /// AC105: the pictures of **different** servers arrive together.
    ///
    /// The refusal the pictures run into is a **per server** quota — one CDN
    /// answers *429* when more than a hundred pictures are asked for in a
    /// short while. A gap between every request, whatever the server, holds
    /// the whole screen back: a playlist whose logos live on a dozen servers
    /// waited a dozen times the gap before the last one arrived, and the car
    /// showed its initials the whole while.
    ///
    /// One server still waits its turn. The others go together.
    func test_AC105_the_pictures_of_different_servers_arrive_together() {
        let artwork = CarPlayArtwork()
        artwork.fetchLogo = { _, completion in completion(UIImage()) }

        let hosts = (0..<8).map { "cdn\($0).example.com" }
        let subjects = hosts.enumerated().map { index, host in
            Channel(name: "Channel \(index)",
                    streamURL: URL(string: "https://example.com/\(index).m3u8")!,
                    groupTitle: "Group",
                    logoURL: URL(string: "https://\(host)/logo.png"))
        }

        let started = Date()
        let settled = expectation(description: "every picture arrived")
        settled.expectedFulfillmentCount = subjects.count
        for subject in subjects {
            artwork.loadLogo(for: subject) { _ in settled.fulfill() }
        }
        wait(for: [settled], timeout: 10)
        let elapsed = Date().timeIntervalSince(started)

        NSLog("DRIVEPLAY %d pictures from %d servers arrived in %.0f ms",
              subjects.count, hosts.count, elapsed * 1000)

        // One gap's worth of time, and not one gap per server.
        XCTAssertLessThan(elapsed, 1.0,
                          "the pictures took \(elapsed)s — the servers' quotas are held against each other")
    }

    /// AC106: the car is told **once** for a batch of pictures, not once per
    /// picture.
    ///
    /// A card that shows a logo is patched by handing the car the row again —
    /// and a row carries every card in it. So a picture that arrives on its
    /// own makes the car take the whole row back, eight times over, for one
    /// logo. The car is asked to redraw what it already has.
    ///
    /// The pictures are told in **batches**: what arrived together goes
    /// together.
    func test_AC106_the_car_is_told_once_for_a_batch_of_pictures() {
        let patcher = CarPlayCardPatcher()

        var applied = 0
        for _ in 0..<8 {
            patcher.add { applied += 1 }
        }

        // The batch waits a moment for the pictures that are still on their
        // way — and then goes out **once**.
        let settled = expectation(description: "the batch went out")
        patcher.add { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(applied, 8, "the batch did not carry every picture")
        XCTAssertEqual(patcher.batchCount, 1,
                       "the car was told \(patcher.batchCount) times for one batch of pictures")
    }
}
