import XCTest
@testable import CarTV

/// The minimised player: the bar at the bottom of the screen that keeps the
/// video's title and its controls in reach while the user browses the app.
///
/// The bar is **docked**, not floating, and it is not a second window: the
/// video keeps playing behind it and the phone draws no picture of its own.
@MainActor
final class MiniPlayerTests: XCTestCase {

    private func channel(_ name: String,
                         group: String = "News",
                         source: UUID = UUID()) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                groupTitle: group,
                sourceId: source)
    }

    /// AC112: the minimised player keeps the video playing.
    func test_AC112_the_minimised_player_keeps_the_video_playing() {
        let manager = PlaybackManager()
        manager.play(channel: channel("AC112"), presentation: .docked)
        XCTAssertFalse(manager.showsMiniPlayer, "the full player is on the screen")

        manager.minimizeToMiniBar()

        XCTAssertTrue(manager.showsMiniPlayer, "the bar is the player's own face now")
        XCTAssertEqual(manager.presentationMode, .mini)
        XCTAssertTrue(manager.isPlaying, "the video keeps playing behind the bar")
        XCTAssertTrue(manager.hasVideoOutput,
                      "the frames need an output of the app's own, or the car's display stays black")
    }

    /// AC113: the bar opens the player again.
    func test_AC113_the_bar_opens_the_player_again() {
        let manager = PlaybackManager()
        manager.play(channel: channel("AC113"), presentation: .docked)
        manager.minimizeToMiniBar()

        manager.expandFromMiniBar()

        XCTAssertEqual(manager.presentationMode, .docked)
        XCTAssertFalse(manager.showsMiniPlayer)
        XCTAssertTrue(manager.isPlaying, "the video was never stopped")
    }

    /// AC114: "next" plays the next channel of the same group, and the player
    /// stays where it was.
    func test_AC114_next_plays_the_next_channel_of_the_same_group() {
        let manager = PlaybackManager()
        let first = channel("AC114 first")
        let second = channel("AC114 second")
        manager.play(channel: first, presentation: .docked)
        manager.minimizeToMiniBar()

        XCTAssertTrue(manager.playNextChannel(in: [first, second]))

        XCTAssertEqual(manager.currentChannel?.id, second.id)
        XCTAssertEqual(manager.presentationMode, .mini,
                       "a next channel played from the bar stays in the bar")
    }

    /// AC115: the list "next" walks is the current channel's own group.
    func test_AC115_the_list_next_walks_is_the_channels_own_group() {
        // A store of its own: the app's own store holds the user's playlist,
        // and a test has no business replacing it.
        let store = PlaylistStore()
        let source = UUID()
        let news = channel("AC115 news", group: "News", source: source)
        let sports = channel("AC115 sports", group: "Sports", source: source)
        store.channels = [news, sports]
        store.rebuildIndex()

        XCTAssertEqual(store.channels(inGroupOf: news).map(\.name), ["AC115 news"],
                       "the next channel is the next one of the channel's own group")
        XCTAssertEqual(store.channels(inGroupOf: sports).map(\.name), ["AC115 sports"])
    }

    /// AC116: a swipe down puts the player away, a drag to the side does not.
    func test_AC116_a_swipe_down_puts_the_player_away() {
        XCTAssertTrue(MiniPlayerSwipe.shouldMinimize(translation: CGSize(width: 10, height: 120)),
                      "a drag downwards minimises the player")
        XCTAssertFalse(MiniPlayerSwipe.shouldMinimize(translation: CGSize(width: 10, height: 20)),
                       "a short drag is not a swipe")
        XCTAssertFalse(MiniPlayerSwipe.shouldMinimize(translation: CGSize(width: 200, height: 80)),
                       "a drag to the side is not a swipe down")
        XCTAssertFalse(MiniPlayerSwipe.shouldMinimize(translation: CGSize(width: 10, height: -120)),
                       "a drag upwards is not a swipe down")
    }
}
