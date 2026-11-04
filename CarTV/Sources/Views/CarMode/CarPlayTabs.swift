import CarPlay
import UIKit

/// What the rows on the car's screen can ask the app to do.
///
/// The builders take the actions as a protocol, so the templates can be built
/// (and tested) without a connected CarPlay scene.
protocol CarPlayTabActions: AnyObject {
    func play(channel: Channel)
    func pushChannels(title: String, channels: [Channel])
    func pushCategories(title: String, categories: [ChannelGroup])
    /// The Home tab's search for a channel — **pushed** onto the stack.
    func pushChannelSearch()
    func togglePicture()
    func togglePlayback()
    func startScreenShare()
    func stopScreenShare()
    /// The car's address bar — pushed onto the stack, never a tab.
    func pushBrowserAddressBar()
    /// A page of the browser opens on the phone.
    func openOnPhone(address: String)
}

/// The four tabs the car's screen is built from.
enum CarPlayTab: String, CaseIterable {
    case home = "Home"
    case favorites = "Favorites"
    case cast = "Cast"
    case browser = "Browser"

    /// The tab's icon — a template image, so the system paints it with its own
    /// colours. A tint of ours paints the whole tab bar green, and the car is
    /// not ours to paint.
    var image: UIImage? {
        UIImage(systemName: symbol)
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .favorites: return "heart.fill"
        case .cast: return "airplayvideo"
        case .browser: return "safari.fill"
        }
    }
}

/// What the Cast tab shows — the real state of the player and of the share.
struct CarPlayCastState {
    var pictureOnCar = false
    var isPlaying = false
    /// True when there is a player at all.
    ///
    /// Without one the picture rows have nothing to move: `castToPhone` and
    /// `togglePlayPause` both give up on a nil player, so the rows would be
    /// dead buttons.
    var hasPlayer = false
    var share: ScreenShareState = .idle
    var shareURL: String?
}

/// The car's four tabs.
///
/// Everything the car shows is built here: the templates are the only thing
/// CarPlay can render, so this is where the layout of the reference interface
/// has to live.
enum CarPlayTemplates {

    /// How many channels a row of cards carries.
    static let cardsPerRow = 8

    /// How many categories the car's Home tab shows.
    ///
    /// CarPlay's own limits allow far more, but every category is a row of
    /// cards and every card is a picture the phone has to draw and the car
    /// has to render: with fifty categories the Home tab was 400 pictures, and
    /// building it took the CarPlay session down. The rest of the catalogue
    /// is still on the car — "All categories" opens every one of them.
    static let homeCategoryLimit = 12

    /// How many items a category of the Home tab costs.
    ///
    /// The card row counts as one item; the "show all" row is another. On the
    /// older systems the channels are rows of their own.
    private static var itemsPerCategory: Int {
        if #available(iOS 26.0, *) { return 2 }
        return cardsPerRow + 1
    }

    /// How many items the "All" section costs.
    private static var itemsForAll: Int {
        if #available(iOS 26.0, *) { return 3 }
        return cardsPerRow + 2
    }

    // MARK: - Home

    /// The catalogue: every channel of the playlist under "All", then the
    /// categories — each with its real count, its own artwork and a way into
    /// every entry it holds.
    static func homeSections(groups: [ChannelGroup],
                             channels: [Channel],
                             owner: CarPlayTabActions?,
                             prefersVideo: Bool) -> [CPListSection] {
        var sections: [CPListSection] = []

        if !channels.isEmpty {
            var items: [CPListTemplateItem] = []

            if #available(iOS 26.0, *) {
                items.append(cardRow(Array(channels.prefix(cardsPerRow)), owner: owner, prefersVideo: prefersVideo))
            } else {
                items.append(contentsOf: Array(channels.prefix(cardsPerRow))
                    .map { channelItem($0, owner: owner, prefersVideo: prefersVideo) })
            }

            // Every category of the catalogue — the ones the Home tab has no
            // room for are still on the car.
            if groups.count > homeCategoryLimit {
                let categories = CPListItem(text: "All categories (\(groups.count))",
                                            detailText: nil,
                                            image: nil)
                categories.accessoryType = .disclosureIndicator
                categories.handler = { _, completion in
                    owner?.pushCategories(title: "Categories", categories: groups)
                    completion()
                }
                items.append(categories)
            }

            // The way into every channel of the playlist.
            let showAll = CPListItem(text: "Show all \(channels.count) channels", detailText: nil, image: nil)
            showAll.accessoryType = .disclosureIndicator
            showAll.handler = { _, completion in
                owner?.pushChannels(title: "All channels", channels: channels)
                completion()
            }
            items.append(showAll)

            let headerImage = channels.first.map { CarPlayArtwork.shared.tile(for: $0, size: CarPlayArtwork.rowSize) }
            let all = CPListSection(items: items,
                                    header: "All",
                                    headerSubtitle: "\(channels.count) channels",
                                    headerImage: headerImage,
                                    headerButton: nil,
                                    sectionIndexTitle: nil)
            if let first = channels.first {
                loadArtwork(for: first, size: CarPlayArtwork.rowSize) { image in
                    CarPlayCardPatcher.shared.add {
                        all.headerImage = image
                    }
                }
            }
            sections.append(all)
        }

        // CarPlay shows only the first `maximumSectionCount` sections **and**
        // only the first `maximumItemCount` items across all of them — and it
        // drops the rest without a word. A playlist with hundreds of
        // categories would therefore lose its tail silently. Nothing is
        // unreachable: every channel is under "All" as well, and every
        // category is under "All categories".
        var used = sections.isEmpty ? 0 : itemsForAll
        var listed = 0
        for group in groups {
            guard sections.count < CPListTemplate.maximumSectionCount else { break }
            guard used + itemsPerCategory <= CPListTemplate.maximumItemCount else { break }
            guard !group.channels.isEmpty else { continue }
            guard listed < homeCategoryLimit else { break }
            sections.append(section(title: group.name,
                                    subtitle: "\(group.channels.count) channels",
                                    shown: Array(group.channels.prefix(cardsPerRow)),
                                    all: group.channels,
                                    owner: owner,
                                    prefersVideo: prefersVideo))
            used += itemsPerCategory
            listed += 1
        }

        if sections.isEmpty {
            sections.append(CPListSection(items: [emptyItem()], header: nil, sectionIndexTitle: nil))
        }
        return sections
    }

    /// One category: its title, its real count, its artwork and its channels.
    private static func section(title: String,
                                 subtitle: String,
                                 shown: [Channel],
                                 all: [Channel],
                                 owner: CarPlayTabActions?,
                                 prefersVideo: Bool) -> CPListSection {
        var items: [CPListTemplateItem] = []

        if #available(iOS 26.0, *) {
            // The reference layout: a horizontally scrollable row of cards.
            items.append(cardRow(shown, owner: owner, prefersVideo: prefersVideo))
        } else {
            items.append(contentsOf: shown.map { channelItem($0, owner: owner, prefersVideo: prefersVideo) })
        }

        // The way into every entry of the category.
        let showAll = CPListItem(text: "Show all \(subtitle)", detailText: nil, image: nil)
        showAll.accessoryType = .disclosureIndicator
        showAll.handler = { _, completion in
            owner?.pushChannels(title: title, channels: all)
            completion()
        }
        items.append(showAll)

        // The artwork of the category is the artwork of its first channel.
        let headerImage = shown.first.map { CarPlayArtwork.shared.tile(for: $0, size: CarPlayArtwork.rowSize) }

        let section = CPListSection(items: items,
                                    header: title,
                                    headerSubtitle: subtitle,
                                    headerImage: headerImage,
                                    headerButton: nil,
                                    sectionIndexTitle: nil)

        // The category's own picture arrives with its first channel's logo —
        // the header is told, the template is not rebuilt.
        if let first = shown.first {
            loadArtwork(for: first, size: CarPlayArtwork.rowSize) { image in
                CarPlayCardPatcher.shared.add {
                    section.headerImage = image
                }
            }
        }

        return section
    }

    // MARK: - Favorites

    /// The favourites the phone holds — the same list, the same instant.
    static func favoritesSections(channels: [Channel],
                                  owner: CarPlayTabActions?,
                                  prefersVideo: Bool) -> [CPListSection] {
        guard !channels.isEmpty else { return [] }
        return [section(title: "Favorites",
                        subtitle: "\(channels.count) channels",
                        shown: Array(channels.prefix(cardsPerRow)),
                        all: channels,
                        owner: owner,
                        prefersVideo: prefersVideo)]
    }

    // MARK: - Cast

    /// Where the picture is, and how the screen is shared.
    static func castSections(state: CarPlayCastState,
                             owner: CarPlayTabActions?,
                             prefersVideo: Bool) -> [CPListSection] {
        // The picture rows only work while there is something to move: with no
        // player `castToPhone` and `togglePlayPause` give up, so the rows
        // would look alive and do nothing. Then the tab says what is missing.
        let pictureRows: [CPListItem]
        if state.hasPlayer {
            let picture = CPListItem(
                text: state.pictureOnCar ? "Picture on the car" : "Picture on the phone",
                detailText: state.pictureOnCar ? "Tap to bring it back to the phone" : "Tap to hand the picture to the car",
                image: UIImage(systemName: state.pictureOnCar ? "car.fill" : "iphone")
            )
            picture.handler = { _, completion in
                owner?.togglePicture()
                completion()
            }

            let playback = CPListItem(
                text: state.isPlaying ? "Pause" : "Play",
                detailText: state.isPlaying ? "The stream stays on the car" : "Start the stream again",
                image: UIImage(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            )
            playback.handler = { _, completion in
                owner?.togglePlayback()
                completion()
            }
            pictureRows = [picture, playback]
        } else {
            pictureRows = [CPListItem(
                text: "Nothing is playing",
                detailText: "Pick a channel on the Home tab",
                image: UIImage(systemName: "tv.slash")
            )]
        }

        let mirror = CPListItem(
            text: "Mirror this phone's screen",
            detailText: shareDetail(state),
            image: UIImage(systemName: "rectangle.inset.filled.and.person.filled")
        )
        // The content behind this row is video — the phone's screen, as a live
        // stream. Only `CPListItem` carries that signal.
        if #available(iOS 26.4, *) {
            mirror.playbackConfiguration = CarPlaySceneDelegate.playbackConfiguration(prefersVideo: prefersVideo)
        }
        mirror.handler = { _, completion in
            owner?.startScreenShare()
            completion()
        }

        let stop = CPListItem(
            text: "Stop mirroring",
            detailText: "Ends the picture the car shows",
            image: UIImage(systemName: "stop.circle")
        )
        stop.handler = { _, completion in
            owner?.stopScreenShare()
            completion()
        }

        // The stop row only exists while there is something to stop: the share
        // refuses to end when it is not running, so the row would do nothing.
        let mirrorRows = state.share.isRunning ? [mirror, stop] : [mirror]

        return [
            CPListSection(items: pictureRows,
                          header: "Picture",
                          headerSubtitle: nil,
                          headerImage: nil,
                          headerButton: nil,
                          sectionIndexTitle: nil),
            CPListSection(items: mirrorRows,
                          header: "Screen mirroring",
                          headerSubtitle: nil,
                          headerImage: nil,
                          headerButton: nil,
                          sectionIndexTitle: nil)
        ]
    }

    /// What the share is doing — the real state, not a promise.
    private static func shareDetail(_ state: CarPlayCastState) -> String {
        switch state.share {
        case .idle:
            return "Start the share from the Control Center"
        case .starting:
            return "Starting…"
        case .sharing:
            return state.shareURL.map { "Sharing \($0)" } ?? "Sharing the phone's screen"
        case .failed(let reason):
            return reason
        }
    }

    // MARK: - Browser

    /// The Browser tab: the way into the address bar, the page the phone shows
    /// now, and the app's own sites.
    ///
    /// The tab itself is a **list**. A `CPSearchTemplate` is the only CarPlay
    /// chrome with a text field, but the tab bar **rejects** one —
    /// `-validateTemplates:` raises an `NSException` and the app dies at every
    /// scene connect — so the address bar is pushed onto the stack instead.
    static func browserSections(currentURL: String,
                                owner: CarPlayTabActions?) -> [CPListSection] {
        var top: [CPListItem] = []

        let addressBar = CPListItem(text: "Search or type a URL",
                                    detailText: "The car's address bar",
                                    image: UIImage(systemName: "magnifyingglass"))
        addressBar.accessoryType = .disclosureIndicator
        addressBar.handler = { _, completion in
            owner?.pushBrowserAddressBar()
            completion()
        }
        top.append(addressBar)

        if !currentURL.isEmpty {
            let now = CPListItem(text: "On the phone now",
                                 detailText: currentURL,
                                 image: UIImage(systemName: "safari.fill"))
            now.handler = { _, completion in
                owner?.openOnPhone(address: currentURL)
                completion()
            }
            top.append(now)
        }

        var sections = [CPListSection(items: top, header: "Browser", sectionIndexTitle: nil)]

        for group in BrowserCatalog.groups {
            let rows = group.items.map { site -> CPListItem in
                let item = CPListItem(text: site.name,
                                      detailText: site.urlString,
                                      image: CarPlayArtwork.shared.siteTile(for: site, size: CarPlayArtwork.rowSize))
                item.handler = { _, completion in
                    owner?.openOnPhone(address: site.urlString)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: rows, header: group.title, sectionIndexTitle: nil))
        }
        return sections
    }

    // MARK: - Rows


    /// A channel row — the list the car plays a channel from.
    static func channelItem(_ channel: Channel,
                            owner: CarPlayTabActions?,
                            prefersVideo: Bool) -> CPListItem {
        let item = CPListItem(
            text: channel.name,
            detailText: channel.groupTitle,
            image: CarPlayArtwork.shared.tile(for: channel, size: CarPlayArtwork.rowSize)
        )
        // iOS 26.4+: tells CarPlay the content behind this row is video, so the
        // system can present the video surface itself.
        if #available(iOS 26.4, *) {
            item.playbackConfiguration = CarPlaySceneDelegate.playbackConfiguration(prefersVideo: prefersVideo)
        }
        item.handler = { _, completion in
            owner?.play(channel: channel)
            completion()
        }
        // The logo arrives after the row was built — the row is told, the
        // template is not rebuilt.
        loadArtwork(for: channel, size: CarPlayArtwork.rowSize) { image in
            item.setImage(image)
        }
        return item
    }

    /// A row of cards — the reference layout, on the cars that know it.
    @available(iOS 26.0, *)
    private static func cardRow(_ channels: [Channel],
                                owner: CarPlayTabActions?,
                                prefersVideo: Bool) -> CPListImageRowItem {
        let size = CarPlayArtwork.cardSize
        let cards: [CPListImageRowItemCardElement] = channels.map { channel in
            let element = CPListImageRowItemCardElement(
                image: CarPlayArtwork.shared.tile(for: channel, size: size),
                showsImageFullHeight: false,
                title: channel.name,
                subtitle: channel.groupTitle,
                // The system's own colour. A tint of our own paints a frame
                // around every card — and the car is not ours to paint.
                tintColor: nil
            )
            if #available(iOS 26.4, *) {
                element.playbackConfiguration = CarPlaySceneDelegate.playbackConfiguration(prefersVideo: prefersVideo)
            }
            return element
        }
        let row = CPListImageRowItem(text: nil, cardElements: cards, allowsMultipleLines: false)
        row.listImageRowHandler = { _, index, completion in
            guard channels.indices.contains(index) else {
                completion()
                return
            }
            owner?.play(channel: channels[index])
            completion()
        }
        // The logos arrive after the screen was built. **The card that shows
        // one is told, the template is not rebuilt**: a rebuild per logo sent
        // the whole catalogue to the car again and again, and that is what
        // took the CarPlay session down.
        //
        // The car is told **once for the whole row**: a car that is handed
        // eight pictures one by one reloads the row eight times.
        for (index, channel) in channels.enumerated() {
            loadArtwork(for: channel, size: size) { image in
                cards[index].image = image
                CarPlayCardPatcher.shared.add { [weak row] in
                    // A fresh array, so the car reloads the row.
                    row?.elements = cards.map { $0 as CPListImageRowItemElement }
                }
            }
        }
        return row
    }

    /// Loads a channel's own picture and hands over the card that shows it.
    ///
    /// Nothing is handed over when the channel has no logo or the download
    /// failed — the placeholder that is already on the screen stays.
    private static func loadArtwork(for channel: Channel,
                                    size: CGSize,
                                    completion: @escaping (UIImage) -> Void) {
        CarPlayArtwork.shared.loadLogo(for: channel) { logo in
            // The card is drawn from **the logo that arrived** — not from a
            // lookup in the cache, which can come back empty for a picture
            // that was just handed over, and then the card would show the
            // initials.
            guard let logo else { return }
            completion(CarPlayArtwork.shared.tile(for: channel, logo: logo, size: size))
        }
    }

    /// The picker of a category: a **list**, because only `CPListItem` carries
    /// the `playbackConfiguration` that asks for the video surface.
    static func channelList(title: String,
                            channels: [Channel],
                            owner: CarPlayTabActions?,
                            prefersVideo: Bool) -> CPListTemplate {
        // CarPlay shows only the first `maximumItemCount` items and drops the
        // rest **without a word** — so a category of 500 channels used to lose
        // everything past the limit. The list is paged instead: the last row
        // offers the next page, and every channel is reachable.
        let perPage = max(1, CPListTemplate.maximumItemCount - 1)
        let page = Array(channels.prefix(perPage))
        var items = page.map { channelItem($0, owner: owner, prefersVideo: prefersVideo) }

        let remaining = channels.count - page.count
        if remaining > 0 {
            let more = CPListItem(text: "More channels (\(remaining) left)",
                                  detailText: nil,
                                  image: UIImage(systemName: "ellipsis.circle"))
            more.accessoryType = .disclosureIndicator
            more.handler = { _, completion in
                owner?.pushChannels(title: title, channels: Array(channels.dropFirst(page.count)))
                completion()
            }
            items.append(more)
        }

        let section = CPListSection(items: items, header: nil, sectionIndexTitle: nil)
        return CPListTemplate(title: title, sections: [section])
    }

    private static func emptyItem() -> CPListItem {
        CPListItem(text: "No channels",
                   detailText: "Add a playlist source in the DrivePlay app",
                   image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash"))
    }

    /// Every category of the catalogue, with the count it really has.
    ///
    /// The Home tab has room for a handful of categories; the rest are here,
    /// so nothing of the catalogue is out of reach on the car.
    static func categoryList(title: String,
                             categories: [ChannelGroup],
                             owner: CarPlayTabActions?) -> CPListTemplate {
        // CarPlay shows only the first `maximumItemCount` items and drops the
        // rest **without a word** — so the list is paged, the same way the
        // channel list is.
        let perPage = max(1, CPListTemplate.maximumItemCount - 1)
        let page = Array(categories.prefix(perPage))
        var items = page.map { group -> CPListItem in
            let item = CPListItem(text: group.name,
                                  detailText: "\(group.channels.count) channels",
                                  image: nil)
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                owner?.pushChannels(title: group.name, channels: group.channels)
                completion()
            }
            return item
        }

        let remaining = categories.count - page.count
        if remaining > 0 {
            let more = CPListItem(text: "More categories (\(remaining) left)",
                                  detailText: nil,
                                  image: UIImage(systemName: "ellipsis.circle"))
            more.accessoryType = .disclosureIndicator
            more.handler = { _, completion in
                owner?.pushCategories(title: title, categories: Array(categories.dropFirst(page.count)))
                completion()
            }
            items.append(more)
        }

        let section = CPListSection(items: items, header: nil, sectionIndexTitle: nil)
        return CPListTemplate(title: title, sections: [section])
    }
}

/// The car's rows, patched in batches.
///
/// Every logo that arrives patches the card that shows it — but a car that is
/// told about **each** picture separately reloads the row again and again,
/// and the session pays for every one of those reloads. The patches are
/// therefore collected and handed over **once per batch**: a car that is told
/// once for eight pictures is a car that is told once.
final class CarPlayCardPatcher {

    /// The one the app uses.
    static let shared = CarPlayCardPatcher()

    /// How long the batch waits for more pictures.
    ///
    /// Long enough that the pictures of one row arrive together, short enough
    /// that the car does not wait for the last one.
    private static let batchDelay: TimeInterval = 0.2

    /// The patches that are waiting for the batch.
    private var pending: [() -> Void] = []
    /// The batches that went out.
    private(set) var batchCount = 0
    /// The work item that will send the batch.
    private var scheduled: DispatchWorkItem?

    /// Adds a patch to the next batch.
    func add(_ patch: @escaping () -> Void) {
        pending.append(patch)
        guard scheduled == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.batchDelay, execute: work)
    }

    /// Sends the batch — on the main thread, because the patches touch the
    /// car's own objects.
    private func flush() {
        scheduled = nil
        let patches = pending
        pending = []
        guard !patches.isEmpty else { return }
        batchCount += 1
        for patch in patches { patch() }
    }
}

/// The car's address bar.
///
/// CarPlay has no web view of its own — Apple does not allow one — so the
/// browser on the car is a **search template**: the search field in its header
/// is the address bar, the results are the app's own sites, and what the user
/// types is opened in the app's browser **on the phone**, where the app's
/// screen share carries it to the car.
///
/// The address bar is **pushed onto the stack**, never a tab: the tab bar
/// rejects a search template and the exception takes the app down.
///
/// The rules are the phone browser's own: a text that is a URL is a URL,
/// anything else is a search.
@MainActor
final class CarPlayBrowserSearch: NSObject, CPSearchTemplateDelegate {

    /// A row of the browser and the address it stands for.
    struct Row {
        let item: CPListItem
        let address: String
    }

    /// The text the user typed — the search template does not keep it.
    private var searchText: String = ""

    /// What a picked row does — the tests replace it, so nothing is loaded.
    var openAddress: (String) -> Void = { address in
        BrowserTabManager.shared.loadURLInActiveTab(address)
        // The car has no web view of its own: the page runs on the phone and
        // reaches the car through the phone's screen share. iOS always asks
        // the **user** to start a share, so the phone has to say that the car
        // is waiting.
        ScreenShareService.shared.carRequestedPage(address)
    }

    /// Called after a result was picked — the car goes back to the list, the
    /// page is on the phone now.
    var dismissAddressBar: () -> Void = {}

    /// The address each result stands for.
    ///
    /// A search result is **not** a list row: the selection comes back
    /// through `searchTemplate(_:selectedResult:completionHandler:)` and the
    /// row's own handler is never called — so the app has to know what the
    /// result was.
    private var results: [ObjectIdentifier: String] = [:]

    /// The row that takes the user back to the browser's list.
    ///
    /// A `CPSearchTemplate` cannot carry a navigation bar button — it does
    /// not conform to `CPBarButtonProviding` — so the way back is a row of
    /// the search's own list.
    private var backRow: CPListItem?

    /// The row that shows the page the phone has open — built **once** and
    /// kept until the page changes.
    ///
    /// The search template is handed a fresh list on every keystroke, and a
    /// row that is built again is a row the car has to be given again.
    private var currentPageRow: (url: String, item: CPListItem)?

    /// The rows of the app's own sites — built **once**.
    ///
    /// The search template hands the car a fresh list on **every keystroke**,
    /// and every row carries a picture at the car's scale, so building them
    /// again for every character is what took the CarPlay scene down. The rows
    /// are built once and only filtered afterwards.
    private static let siteRows: [Row] = {
        var rows: [Row] = []
        for group in BrowserCatalog.groups {
            for site in group.items {
                rows.append(Row(item: CPListItem(text: site.name,
                                                  detailText: site.urlString,
                                                  image: CarPlayArtwork.shared.siteTile(for: site, size: CarPlayArtwork.rowSize)),
                                 address: site.urlString))
            }
        }
        return rows
    }()

    /// The rows the browser offers: the page the phone shows now, then the
    /// app's own sites.
    func rows(currentURL: String) -> [Row] {
        var rows: [Row] = []
        if !currentURL.isEmpty {
            let item: CPListItem
            if let known = currentPageRow, known.url == currentURL {
                item = known.item
            } else {
                item = CPListItem(text: "On the phone now",
                                  detailText: currentURL,
                                  image: UIImage(systemName: "safari.fill"))
                currentPageRow = (currentURL, item)
            }
            rows.append(Row(item: item, address: currentURL))
        }
        rows.append(contentsOf: Self.siteRows)
        return rows
    }

    public func searchTemplate(_ searchTemplate: CPSearchTemplate,
                               updatedSearchText searchText: String,
                               completionHandler: @escaping ([CPListItem]) -> Void) {
        self.searchText = searchText
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var offered: [Row] = []
        // The way back — the first row, **always**: a search the user cannot
        // get out of is a dead end, and typing must not take the way out
        // away.
        let back = backRow ?? CPListItem(text: "Back to sites",
                                          detailText: nil,
                                          image: UIImage(systemName: "chevron.backward"))
        backRow = back
        offered.append(Row(item: back, address: ""))
        // What the user typed is the first row: it opens the text the way the
        // phone's browser does — a URL is a URL, anything else is a search.
        if !query.isEmpty {
            offered.append(Row(item: CPListItem(text: "Open \"\(query)\"",
                                                 detailText: query,
                                                 image: UIImage(systemName: "magnifyingglass")),
                               address: query))
        }
        for row in rows(currentURL: BrowserTabManager.shared.activeTabURL) {
            guard query.isEmpty || row.address.localizedCaseInsensitiveContains(query) else { continue }
            offered.append(row)
        }

        results = [:]
        for row in offered {
            // The way back is not an address — it stands for the list.
            if let back = backRow, row.item === back { continue }
            results[ObjectIdentifier(row.item)] = row.address
        }
        completionHandler(offered.map(\.item))
    }

    public func searchTemplate(_ searchTemplate: CPSearchTemplate,
                               selectedResult item: CPListItem,
                               completionHandler: @escaping () -> Void) {
        if let back = backRow, item === back {
            completionHandler()
            dismissAddressBar()
            return
        }
        if let address = results[ObjectIdentifier(item)] {
            openOnPhone(address)
        } else {
            NSLog("DRIVEPLAY the selected browser result stands for no address")
        }
        completionHandler()
        dismissAddressBar()
    }

    public func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        openOnPhone(query)
        dismissAddressBar()
    }

    /// Opens the address in the app's own browser **on the phone** and arms
    /// the share that carries the page to the car.
    ///
    /// The car cannot draw a page of its own, so the page reaches it through
    /// the phone's screen share.
    private func openOnPhone(_ address: String) {
        guard !address.isEmpty else { return }
        openAddress(address)
    }
}
