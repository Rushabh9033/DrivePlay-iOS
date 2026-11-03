import XCTest
@testable import CarTV

/// The picture on the car travels as AirPlay video: the car's display is an
/// AirPlay destination, so the player has to allow external playback on every
/// path — a CarPlay video app "needs to support AirPlay video streaming"
/// ("Rev up your CarPlay app", WWDC26).
@MainActor
final class PlaybackManagerTests: XCTestCase {

    /// AC49: a channel played for the car is offered to the car's display.
    func test_AC49_the_player_offers_the_video_to_the_car() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC49",
                              streamURL: URL(string: "https://example.com/ac49.m3u8")!)

        manager.play(channel: channel, presentation: .hidden)

        XCTAssertEqual(manager.player?.allowsExternalPlayback, true)
    }

    /// AC51: the picture can be brought back from the car to the phone.
    func test_AC51_the_picture_can_be_brought_back_from_the_car() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC51",
                              streamURL: URL(string: "https://example.com/ac51.m3u8")!)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertFalse(manager.isPlayingOnCar)

        manager.castToPhone()

        XCTAssertFalse(manager.isPlayingOnCar)
        XCTAssertEqual(manager.player?.allowsExternalPlayback, false)
    }

    /// AC52: the player keeps an output while the phone shows no picture.
    ///
    /// A video-only item never renders without an output — the car's display
    /// would stay black.
    func test_AC52_the_player_keeps_an_output_while_the_phone_shows_no_picture() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC52",
                              streamURL: URL(string: "https://example.com/ac52.m3u8")!)

        manager.play(channel: channel, presentation: .hidden)
        XCTAssertTrue(manager.hasVideoOutput)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertFalse(manager.hasVideoOutput)
    }

    /// AC53: the picture keeps playing when the phone is minimised.
    func test_AC53_the_picture_keeps_playing_when_the_phone_is_minimised() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC53",
                              streamURL: URL(string: "https://example.com/ac53.m3u8")!)

        manager.play(channel: channel, presentation: .hidden)
        manager.keepPlayingInTheBackground()

        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.player?.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        XCTAssertTrue(manager.hasVideoOutput)
    }

    /// AC54: the car takes the picture — the phone stops drawing it and the
    /// output follows, so the item keeps rendering.
    func test_AC54_the_car_takes_the_picture() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC54",
                              streamURL: URL(string: "https://example.com/ac54.m3u8")!)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertFalse(manager.hasVideoOutput)

        manager.handOffToCar()

        XCTAssertEqual(manager.presentationMode, .hidden)
        XCTAssertTrue(manager.hasVideoOutput)
    }

    /// AC64: the picture can go back to the car after it came back to the phone.
    ///
    /// Taking the picture back stops the player from leaving the phone, so the
    /// round trip has to offer the video to the car again — otherwise the route
    /// is picked and nothing happens.
    func test_AC64_the_picture_can_go_back_to_the_car_after_it_came_back() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC64",
                              streamURL: URL(string: "https://example.com/ac64.m3u8")!)

        manager.play(channel: channel, presentation: .hidden)
        manager.castToPhone()
        XCTAssertEqual(manager.player?.allowsExternalPlayback, false)

        manager.handOffToCar()

        XCTAssertEqual(manager.player?.allowsExternalPlayback, true)
        XCTAssertEqual(manager.presentationMode, .hidden)
    }

    /// AC103: a video the user starts on the phone goes to the car's display
    /// at once — the car is there, so the picture belongs to it.
    func test_AC103_a_video_started_on_the_phone_goes_to_the_car_at_once() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC103",
                              streamURL: URL(string: "https://example.com/ac103.m3u8")!)

        manager.isCarConnected = true
        manager.play(channel: channel, presentation: .docked)

        XCTAssertEqual(manager.presentationMode, .hidden,
                       "the phone keeps no picture — the car shows the video")
        XCTAssertTrue(manager.hasVideoOutput,
                      "the item needs an output of its own, or the car's display stays black")
        XCTAssertEqual(manager.player?.allowsExternalPlayback, true)

        // Without a car the video stays on the phone.
        manager.isCarConnected = false
        manager.play(channel: channel, presentation: .docked)
        XCTAssertEqual(manager.presentationMode, .docked)
    }
}
