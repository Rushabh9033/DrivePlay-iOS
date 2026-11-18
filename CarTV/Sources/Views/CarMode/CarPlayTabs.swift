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
    func openBrowser(url: URL?)
    func closeBrowser()
    func pushBrowserAddressBar()
    func pushCurrentPageLinks()
    func pushCurrentPageInputs()
}

/// The four tabs the car's screen is built from: Home, Favorites, Cast, and Browser.
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
        case .browser: return "globe"
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

    // MARK: - Browser

    /// The dedicated Safari-like browser section on CarPlay.
    @MainActor
    static func browserSections(owner: CarPlayTabActions?) -> [CPListSection] {
        var topItems: [CPListTemplateItem] = []

        let searchItem = CPListItem(
            text: "🔍 Search or Type URL...",
            detailText: "Search Google or enter any website address",
            image: UIImage(systemName: "magnifyingglass")
        )
        searchItem.accessoryType = .disclosureIndicator
        searchItem.handler = { _, completion in
            owner?.pushBrowserAddressBar()
            completion()
        }
        topItems.append(searchItem)

        let topSection = CPListSection(items: topItems, header: "Safari Web Search", sectionIndexTitle: nil)

        let bookmarks: [(name: String, desc: String, url: String, icon: String)] = [
            ("Google", "Search anything on the web", "https://www.google.com", "globe"),
            ("YouTube", "Watch videos & livestreams", "https://www.youtube.com", "play.rectangle.fill"),
            ("Wikipedia", "The free encyclopedia", "https://www.wikipedia.org", "books.vertical.fill"),
            ("Reddit", "Dive into anything", "https://www.reddit.com", "bubble.left.and.bubble.right.fill"),
            ("ESPN", "Live scores, sports news and updates", "https://www.espn.com", "sportscourt.fill"),
            ("BBC News", "World news and reporting", "https://www.bbc.com", "newspaper.fill"),
            ("Netflix", "Movies & TV series", "https://www.netflix.com", "film.fill"),
            ("ChatGPT", "AI assistant & conversations", "https://chat.openai.com", "sparkles")
        ]

        var bookmarkItems: [CPListTemplateItem] = []
        for site in bookmarks {
            let item = CPListItem(
                text: site.name,
                detailText: site.desc,
                image: UIImage(systemName: site.icon)
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                if let u = URL(string: site.url) {
                    owner?.openBrowser(url: u)
                }
                completion()
            }
            bookmarkItems.append(item)
        }

        let bookmarkSection = CPListSection(items: bookmarkItems, header: "Popular Websites", sectionIndexTitle: nil)

        return [topSection, bookmarkSection]
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
