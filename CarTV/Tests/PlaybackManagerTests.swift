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
    ///
    /// The phone gives the picture up when the **system** says the car has it,
    /// not when the app asks: a car whose video endpoint is not ready yet
    /// would otherwise leave the video on neither screen.
    func test_AC54_the_car_takes_the_picture() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC54",
                              streamURL: URL(string: "https://example.com/ac54.m3u8")!)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertFalse(manager.hasVideoOutput)

        manager.handOffToCar()
        XCTAssertEqual(manager.presentationMode, .docked,
                       "the phone keeps the picture until the system says the car has it")

        manager.systemSaysPictureIsOnCar(true)

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
        // The phone gives the picture up when the system says the car has it.
        manager.systemSaysPictureIsOnCar(true)
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

        // The route is open at once — the system can take the picture now.
        XCTAssertEqual(manager.player?.allowsExternalPlayback, true)
        XCTAssertTrue(manager.isHandingOffToCar,
                      "the car has not taken the picture yet, so the switch says so")

        // The system says the car has it: the phone stops drawing it, and the
        // item needs an output of its own, or the car's display stays black.
        manager.systemSaysPictureIsOnCar(true)
        XCTAssertEqual(manager.presentationMode, .hidden,
                       "the phone keeps no picture — the car shows the video")
        XCTAssertTrue(manager.hasVideoOutput,
                      "the item needs an output of its own, or the car's display stays black")

        // Without a car the video stays on the phone.
        manager.isCarConnected = false
        manager.play(channel: channel, presentation: .docked)
        XCTAssertEqual(manager.presentationMode, .docked)
    }

    /// AC107: the picture is never on neither screen.
    ///
    /// The hand-off used to hide the phone's picture **straight away**: if the
    /// car's video endpoint was not ready yet, the video was on the phone's
    /// layer *and* on the car's — and the user saw "sometimes only in the car,
    /// sometimes only on the phone". The phone keeps the picture until the
    /// system says the car has it, and takes it back when the user asks.
    func test_AC107_the_picture_is_never_on_neither_screen() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC107",
                              streamURL: URL(string: "https://example.com/ac107.m3u8")!)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertEqual(manager.presentationMode, .docked, "the picture is on the phone")

        manager.handOffToCar()
        XCTAssertEqual(manager.presentationMode, .docked,
                       "the picture is still on the phone — the car has not confirmed it")

        manager.systemSaysPictureIsOnCar(true)
        XCTAssertEqual(manager.presentationMode, .hidden, "the picture is on the car")

        manager.castToPhone()
        XCTAssertEqual(manager.presentationMode, .docked, "the picture is back on the phone")
    }

    /// AC108: the picture the user took back does not jump back to the car.
    ///
    /// The hand-off offers the picture again and again for a while (the car's
    /// video endpoint appears late), and that ladder was never stopped: the
    /// picture the user had taken back to the phone jumped back to the car a
    /// few seconds later, on its own.
    func test_AC108_the_picture_taken_back_does_not_jump_back_to_the_car() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC108",
                              streamURL: URL(string: "https://example.com/ac108.m3u8")!)

        manager.isCarConnected = true
        manager.play(channel: channel, presentation: .docked)
        manager.handOffToCar()
        let offers = manager.offerCount

        manager.castToPhone()

        // The ladder of the hand-off had its chance — and it may not offer
        // the picture again.
        let settled = expectation(description: "the ladder had its chance")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(manager.offerCount, offers,
                       "the picture was offered to the car again after the user took it back")
        XCTAssertEqual(manager.player?.allowsExternalPlayback, false)
        XCTAssertFalse(manager.isHandingOffToCar)
    }

    /// AC109: the now-playing artwork is drawn once per channel.
    ///
    /// The now-playing info is refreshed four times a second while a video
    /// plays, and the artwork was **drawn** every time: a 512×512 gradient
    /// with a symbol and three lines of text, on the main thread, four times
    /// a second. That is what made the phone stutter while a video played.
    func test_AC109_the_now_playing_artwork_is_drawn_once_per_channel() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC109",
                              streamURL: URL(string: "https://example.com/ac109.m3u8")!)

        manager.play(channel: channel, presentation: .docked)
        XCTAssertEqual(manager.artworkDrawCount, 1,
                       "the artwork was drawn \(manager.artworkDrawCount) times for one channel")

        for _ in 0..<40 {
            manager.updateNowPlayingInfo()
        }

        XCTAssertEqual(manager.artworkDrawCount, 1,
                       "the artwork was drawn again while nothing about it had changed")
    }

    /// AC110: a video that has just started is not offered to the car twice.
    ///
    /// The item is attached with the route already open, so the system has
    /// looked at it. Offering the picture again straight away would build the
    /// player a second time — the stutter that made a start feel laggy.
    func test_AC110_a_video_that_has_just_started_is_not_offered_twice() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC110",
                              streamURL: URL(string: "https://example.com/ac110.m3u8")!)

        manager.isCarConnected = true
        manager.play(channel: channel, presentation: .docked)
        XCTAssertEqual(manager.offerCount, 0,
                       "the picture was offered again right after the video started")

        // The button asks for the picture — **now** it is offered.
        XCTAssertTrue(manager.playOnCarDisplay())
        XCTAssertEqual(manager.offerCount, 1)
    }

    /// AC139: a video the **car** asked for is offered to the car's display
    /// again and again.
    ///
    /// The car's video endpoint appears a moment after the scene connects and
    /// the route is only looked at when the picture is offered — so a picture
    /// offered once, at the moment the row is tapped, finds no endpoint and
    /// the car's screen stays black. The play used to carry **no** ladder at
    /// all when the car asked for it.
    func test_AC139_a_video_the_car_asked_for_is_offered_to_the_car_again() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC139",
                              streamURL: URL(string: "https://example.com/ac139.m3u8")!)

        manager.isCarConnected = true
        manager.play(channel: channel, presentation: .hidden)

        XCTAssertTrue(manager.isHandingOffToCar,
                      "the car's own play was not handed off at all, so the car's screen stays black")

        // The first offer comes after the video had its chance to start.
        let settled = expectation(description: "the ladder had its chance")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { settled.fulfill() }
        wait(for: [settled], timeout: 8)

        XCTAssertGreaterThan(manager.offerCount, 0,
                             "the picture was never offered to the car again")
    }

    /// AC140: the phone's screen share reaches the car's display.
    ///
    /// The share is the only way a **page** reaches the car (CarPlay has no
    /// web view of its own), and the share plays through the very same
    /// player — so it has to be handed off to the car like any other video.
    func test_AC140_the_screen_share_is_offered_to_the_car() {
        let manager = PlaybackManager()
        let url = URL(string: "http://127.0.0.1:47311/abc/live.m3u8")!

        manager.isCarConnected = true
        manager.playScreenShare(url: url, title: "iPhone screen")

        XCTAssertEqual(manager.player?.allowsExternalPlayback, true,
                       "the share cannot leave the phone without the route open")
        XCTAssertTrue(manager.isHandingOffToCar,
                      "the share played on the phone and the car's display stayed black")
        XCTAssertEqual(manager.presentationMode, .hidden,
                       "the phone must not show the video it is capturing")
    }
}
