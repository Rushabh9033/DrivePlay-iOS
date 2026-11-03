import CarPlay
import UIKit

/// What the rows on the car's screen can ask the app to do.
///
/// The builders take the actions as a protocol, so the templates can be built
/// (and tested) without a connected CarPlay scene.
protocol CarPlayTabActions: AnyObject {
    func play(channel: Channel)
    func pushChannels(title: String, channels: [Channel])
    func presentSearch()
    func togglePicture()
    func togglePlayback()
    func startScreenShare()
    func stopScreenShare()
    func openOnPhone(url: String)
}

/// The four tabs the car's screen is built from.
enum CarPlayTab: String, CaseIterable {
    case home = "Home"
    case favorites = "Favorites"
    case cast = "Cast"
    case browser = "Browser"

    /// The tab's icon — drawn in the app's accent, because the system owns the
    /// tab bar's selection marker.
    var image: UIImage? {
        UIImage(systemName: symbol)?.withTintColor(CarPlayPalette.accent, renderingMode: .alwaysOriginal)
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

    // MARK: - Home

    /// The catalogue: every channel of the playlist under "All", then the
    /// categories — each with its real count, its own artwork and a way into
    /// every entry it holds.
    static func homeSections(groups: [ChannelGroup],
                             channels: [Channel],
                             owner: CarPlayTabActions?,
                             prefersVideo: Bool,
                             onArtwork: (() -> Void)? = nil) -> [CPListSection] {
        var sections: [CPListSection] = []

        if !channels.isEmpty {
            sections.append(section(title: "All",
                                    subtitle: "\(channels.count) channels",
                                    shown: Array(channels.prefix(cardsPerRow)),
                                    all: channels,
                                    owner: owner,
                                    prefersVideo: prefersVideo,
                                    onArtwork: onArtwork))
        }

        // CarPlay shows only the first `maximumSectionCount` sections — a
        // playlist with hundreds of categories would lose the tail silently.
        // Nothing is unreachable: every channel is under "All" as well.
        let room = max(0, CPListTemplate.maximumSectionCount - sections.count)
        for group in groups.prefix(room) where !group.channels.isEmpty {
            sections.append(section(title: group.name,
                                    subtitle: "\(group.channels.count) channels",
                                    shown: Array(group.channels.prefix(cardsPerRow)),
                                    all: group.channels,
                                    owner: owner,
                                    prefersVideo: prefersVideo,
                                    onArtwork: onArtwork))
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
                                 prefersVideo: Bool,
                                 onArtwork: (() -> Void)?) -> CPListSection {
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

        fetchArtwork(for: shown, onLoaded: onArtwork)

        return CPListSection(items: items,
                             header: title,
                             headerSubtitle: subtitle,
                             headerImage: headerImage,
                             headerButton: nil,
                             sectionIndexTitle: nil)
    }

    // MARK: - Favorites

    /// The favourites the phone holds — the same list, the same instant.
    static func favoritesSections(channels: [Channel],
                                  owner: CarPlayTabActions?,
                                  prefersVideo: Bool,
                                  onArtwork: (() -> Void)? = nil) -> [CPListSection] {
        guard !channels.isEmpty else { return [] }
        return [section(title: "Favorites",
                        subtitle: "\(channels.count) channels",
                        shown: Array(channels.prefix(cardsPerRow)),
                        all: channels,
                        owner: owner,
                        prefersVideo: prefersVideo,
                        onArtwork: onArtwork)]
    }

    // MARK: - Cast

    /// Where the picture is, and how the screen is shared.
    static func castSections(state: CarPlayCastState,
                             owner: CarPlayTabActions?,
                             prefersVideo: Bool) -> [CPListSection] {
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

        return [
            CPListSection(items: [picture, playback],
                          header: "Picture",
                          headerSubtitle: nil,
                          headerImage: nil,
                          headerButton: nil,
                          sectionIndexTitle: nil),
            CPListSection(items: [mirror, stop],
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

    /// The browser the car is allowed to have.
    ///
    /// CarPlay has no web view — Apple does not allow one — so the car cannot
    /// show a page of its own. What it *can* do is open a real site of the
    /// app's own browser **on the phone**, where the app's screen share carries
    /// the picture to the car.
    static func browserSections(currentURL: String, owner: CarPlayTabActions?) -> [CPListSection] {
        let now = CPListItem(
            text: "On the phone now",
            detailText: currentURL.isEmpty ? "No page is open" : currentURL,
            image: UIImage(systemName: "safari.fill")
        )
        now.handler = { _, completion in
            owner?.openOnPhone(url: currentURL)
            completion()
        }

        var sections: [CPListSection] = [
            CPListSection(items: [now],
                          header: "Phone",
                          headerSubtitle: nil,
                          headerImage: nil,
                          headerButton: nil,
                          sectionIndexTitle: nil)
        ]

        for group in BrowserCatalog.groups {
            let items = group.items.map { site -> CPListItem in
                let item = CPListItem(
                    text: site.name,
                    detailText: site.urlString,
                    image: CarPlayArtwork.shared.siteTile(for: site, size: CarPlayArtwork.rowSize)
                )
                item.handler = { _, completion in
                    owner?.openOnPhone(url: site.urlString)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items,
                                          header: group.title,
                                          headerSubtitle: nil,
                                          headerImage: nil,
                                          headerButton: nil,
                                          sectionIndexTitle: nil))
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
        return item
    }

    /// A row of cards — the reference layout, on the cars that know it.
    @available(iOS 26.0, *)
    private static func cardRow(_ channels: [Channel],
                                owner: CarPlayTabActions?,
                                prefersVideo: Bool) -> CPListImageRowItem {
        let size = CarPlayArtwork.cardSize
        let elements = channels.map { channel -> CPListImageRowItemCardElement in
            let element = CPListImageRowItemCardElement(
                image: CarPlayArtwork.shared.tile(for: channel, size: size),
                showsImageFullHeight: false,
                title: channel.name,
                subtitle: channel.groupTitle,
                tintColor: CarPlayPalette.accent
            )
            if #available(iOS 26.4, *) {
                element.playbackConfiguration = CarPlaySceneDelegate.playbackConfiguration(prefersVideo: prefersVideo)
            }
            return element
        }
        let row = CPListImageRowItem(text: nil, cardElements: elements, allowsMultipleLines: false)
        row.listImageRowHandler = { _, index, completion in
            guard channels.indices.contains(index) else {
                completion()
                return
            }
            owner?.play(channel: channels[index])
            completion()
        }
        return row
    }

    /// The picker of a category: a **list**, because only `CPListItem` carries
    /// the `playbackConfiguration` that asks for the video surface.
    static func channelList(title: String,
                            channels: [Channel],
                            owner: CarPlayTabActions?,
                            prefersVideo: Bool) -> CPListTemplate {
        // The list shows as many rows as CarPlay itself is willing to show —
        // a template with more is silently cut off by the system.
        let items = channels.prefix(CPListTemplate.maximumItemCount)
            .map { channelItem($0, owner: owner, prefersVideo: prefersVideo) }
        let section = CPListSection(items: items, header: nil, sectionIndexTitle: nil)
        return CPListTemplate(title: title, sections: [section])
    }

    private static func emptyItem() -> CPListItem {
        CPListItem(text: "No channels",
                   detailText: "Add a playlist source in the DrivePlay app",
                   image: UIImage(systemName: "antenna.radiowaves.left.and.right.slash"))
    }

    /// Fetches the logos of the channels on the screen. The completion runs
    /// only when a logo actually arrived.
    private static func fetchArtwork(for channels: [Channel], onLoaded: (() -> Void)?) {
        guard let onLoaded else { return }
        for channel in channels {
            CarPlayArtwork.shared.fetchTile(for: channel) { onLoaded() }
        }
    }
}
