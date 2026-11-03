import AVFoundation
import CoreVideo
import Network
import UIKit
import XCTest
@testable import CarTV

/// AC29: the screen share serves a live stream a player can read.
/// AC30: the share says so when the screen cannot be recorded.
final class ScreenShareTests: XCTestCase {

    /// The port the relay tests listen on.
    ///
    /// The app listens on the production port from launch, so a test that
    /// bound it would be talking to the app's own listener instead of its own.
    private static let relayPort: UInt16 = 47312

    /// The port the "the relay cannot listen" test takes for itself.
    private static let takenPort: UInt16 = 47313

    /// AC29: the screen share serves a live HLS stream over HTTP.
    ///
    /// This is the whole chain minus the capture: the frames go in, the playlist
    /// and its fragments come out over HTTP — the same stream the car plays.
    func test_AC29_the_screen_share_serves_a_live_hls_stream() async throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")
        let server = ScreenStreamServer(writer: writer)

        let listening = expectation(description: "the server is listening")
        var port: UInt16 = 0
        try server.start { boundPort in
            port = boundPort
            listening.fulfill()
        }
        await fulfillment(of: [listening], timeout: 5)
        let token = server.token

        // Three seconds of frames, paced like a real capture: the encoder drops
        // frames that arrive faster than it can encode them, and a dropped frame
        // never advances the media clock.
        for index in 0..<90 {
            let buffer = try makePixelBuffer(width: 320, height: 240)
            writer.append(
                pixelBuffer: buffer,
                presentationTime: CMTime(value: CMTimeValue(index), timescale: 30)
            )
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        try await waitUntil("the encoder produced a fragment") { writer.playlist() != nil }

        // The playlist is served over HTTP, and only with the token in the path.
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(token)/live.m3u8"))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("#EXTM3U"), "not a playlist: \(text)")
        XCTAssertTrue(text.contains("#EXT-X-MAP"), "no initialisation segment: \(text)")
        XCTAssertTrue(text.contains("#EXTINF"), "no media segment: \(text)")
        XCTAssertFalse(text.contains("#EXT-X-ENDLIST"), "a live playlist must not end")

        let withoutToken = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/live.m3u8"))
        let (_, denied) = try await URLSession.shared.data(from: withoutToken)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404, "the stream must not be readable without the token")

        // The initialisation segment and a media fragment are served too.
        let initialisation = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(token)/init.mp4"))
        let (initData, initResponse) = try await URLSession.shared.data(from: initialisation)
        XCTAssertEqual((initResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(initData.isEmpty)

        let fragment = try XCTUnwrap(writer.currentFragments.first)
        let fragmentURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(token)/frag-\(fragment.index).m4s"))
        let (fragmentData, fragmentResponse) = try await URLSession.shared.data(from: fragmentURL)
        XCTAssertEqual((fragmentResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(fragmentData.isEmpty)
    }

    /// AC30: a device that cannot record the screen says so, instead of
    /// pretending the share started.
    @MainActor
    func test_AC30_the_share_reports_a_device_that_cannot_record() async throws {
        let service = ScreenShareService()
        service.start(captureAvailable: false)

        guard case .failed(let message) = service.state else {
            return XCTFail("expected the share to fail, got \(service.state)")
        }
        XCTAssertTrue(message.contains("cannot record"), "unhelpful message: \(message)")
    }

    /// AC31: the demo picture travels the same path as a real share.
    ///
    /// The CarPlay Simulator has no capturable screen, so the demo is the only
    /// way to check the whole chain there.
    func test_AC31_the_demo_stream_feeds_the_same_encoder() async throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")
        let demo = DemoFrameSource()
        demo.start(writer: writer)
        defer { demo.stop() }

        try await waitUntil("the demo produced a fragment") { writer.playlist() != nil }

        let text = String(decoding: try XCTUnwrap(writer.playlist()), as: UTF8.self)
        XCTAssertTrue(text.contains("#EXT-X-MAP"), "no initialisation segment: \(text)")
        XCTAssertTrue(text.contains("#EXTINF"), "no media segment: \(text)")
    }

    /// AC32: the player CarPlay draws can play the stream the app serves.
    ///
    /// This is the last link of the chain: the car's screen shows what the
    /// app's own `AVPlayer` plays.
    ///
    /// The player needs a video output. A video-only item never renders
    /// without an `AVPlayerLayer` — CoreMedia logs "video-only item is waiting
    /// for video output" and the playhead stays at zero — so the test attaches
    /// one, exactly as the app's player view does.
    @MainActor
    func test_AC32_the_stream_the_app_serves_is_playable_by_the_player() async throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")
        let server = ScreenStreamServer(writer: writer)

        let listening = expectation(description: "the server is listening")
        var port: UInt16 = 0
        try server.start { boundPort in
            port = boundPort
            listening.fulfill()
        }
        await fulfillment(of: [listening], timeout: 5)

        let demo = DemoFrameSource()
        demo.start(writer: writer)
        defer { demo.stop() }

        try await waitUntil("the encoder produced a fragment") { writer.playlist() != nil }

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(server.token)/live.m3u8"))
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)

        // The video output.
        let window = UIWindow(frame: UIScreen.main.bounds)
        let view = UIView(frame: window.bounds)
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        player.play()

        try await waitUntil("the picture advanced", timeout: 30) {
            player.currentTime().seconds > 0.5
        }
        XCTAssertGreaterThan(player.currentTime().seconds, 0.5, "the picture did not advance")
    }

    /// AC34: a capture that delivers no frame hands over to the demo picture.
    ///
    /// The Simulator has no screen to record: the capture ends at once, without a
    /// frame. The share must not die there — the chain is the same, only the
    /// source differs, so the demo takes over and the car still gets a picture.
    ///
    /// On a phone the real capture waits for the user's consent and never ends
    /// on its own, so the case is driven through the capture seam: a capture
    /// that ends without a frame.
    @MainActor
    func test_AC34_a_capture_without_frames_falls_back_to_the_demo() async throws {
        let service = ScreenShareService(capture: { _, onEnd in onEnd(nil) })
        service.start(captureAvailable: true)

        try await waitUntil("the demo took over", timeout: 30) { service.state == .sharing }
        XCTAssertTrue(service.isDemo, "the demo picture did not take over")
        service.stop()
    }

    /// AC37: the broadcast extension can tell the app where its stream is.
    ///
    /// The two live in different processes and share no container, so the
    /// address travels over the loopback interface in one line.
    func test_AC37_the_relay_announcement_carries_the_stream_address() {
        let line = ScreenRelayEndpoint.announcement(port: 51234, token: "ab12cd34")

        let parsed = ScreenRelayEndpoint.parse(line)
        XCTAssertEqual(parsed?.port, 51234)
        XCTAssertEqual(parsed?.token, "ab12cd34")
        XCTAssertNil(ScreenRelayEndpoint.parse("not an announcement"), "rubbish must not be taken for an address")
        XCTAssertNil(ScreenRelayEndpoint.parse("51234"), "an address without a token is not one")
    }

    /// AC38: the app takes the address the extension announces.
    ///
    /// This is the half of the relay that runs in the app: the extension opens a
    /// connection to the app's listener and sends the address, and the app picks
    /// the stream up from there.
    func test_AC38_the_app_takes_the_announcement_of_the_broadcast_extension() async throws {
        let listener = ScreenRelayListener(port: Self.relayPort)
        let taken = expectation(description: "the announcement was taken")
        var announced: (port: UInt16, token: String)?
        listener.onStream = { port, token in
            announced = (port, token)
            taken.fulfill()
        }
        try listener.start()
        defer { listener.stop() }

        let controlPort = try XCTUnwrap(NWEndpoint.Port(rawValue: Self.relayPort))
        let connection = NWConnection(host: .ipv4(.loopback), port: controlPort, using: .tcp)
        let sent = expectation(description: "the announcement was sent")
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let line = ScreenRelayEndpoint.announcement(port: 51234, token: "ab12cd34")
            connection.send(content: Data(line.utf8), completion: .contentProcessed { _ in sent.fulfill() })
        }
        connection.start(queue: DispatchQueue(label: "com.rushabh.cartvv.tests.relay"))

        await fulfillment(of: [taken, sent], timeout: 10)
        XCTAssertEqual(announced?.port, 51234)
        XCTAssertEqual(announced?.token, "ab12cd34")
    }

    /// AC39: the relay waits for a broadcast without wedging the share.
    ///
    /// The relay only listens — it shares nothing until the broadcast
    /// extension announces its stream. A capture or the demo picture must
    /// therefore still be startable while it waits, and the waiting has to be
    /// visible: otherwise the user does not know that the car waits for them.
    @MainActor
    func test_AC39_the_relay_waits_for_a_broadcast_without_blocking_the_share() async throws {
        let service = ScreenShareService(relay: ScreenRelayListener(port: Self.relayPort))
        service.startRelay()
        XCTAssertTrue(service.isWaitingForBroadcast, "the app does not say that it waits for a broadcast")

        // The capture path still works while the relay waits.
        service.start(captureAvailable: false)
        guard case .failed(let message) = service.state else {
            return XCTFail("expected the capture to fail, got \(service.state)")
        }
        XCTAssertTrue(message.contains("cannot record"), "unhelpful message: \(message)")
        service.stopRelay()
    }

    /// AC40: the announcement of the broadcast extension starts the share.
    ///
    /// This is the moment the phone's screen reaches the car: the extension
    /// announces the address of its stream, the app plays it, and the car
    /// draws what the app plays.
    @MainActor
    func test_AC40_the_announcement_of_the_broadcast_extension_starts_the_share() async throws {
        let service = ScreenShareService(relay: ScreenRelayListener(port: Self.relayPort))
        service.startRelay()

        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: Self.relayPort))
        let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        let sent = expectation(description: "the announcement was sent")
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            let line = ScreenRelayEndpoint.announcement(port: 51234, token: "ab12cd34")
            connection.send(content: Data(line.utf8), completion: .contentProcessed { _ in sent.fulfill() })
        }
        connection.start(queue: DispatchQueue(label: "com.rushabh.cartvv.tests.relay.share"))

        await fulfillment(of: [sent], timeout: 10)
        try await waitUntil("the share started") { service.state == .sharing }
        XCTAssertFalse(service.isWaitingForBroadcast, "the app still waits for a broadcast")
        service.stop()
        service.stopRelay()
    }

    /// AC41: the car's screen-share row starts the demo picture on the Simulator.
    ///
    /// The row cannot record the screen — iOS refuses while CarPlay is
    /// connected — so it waits for a broadcast. The Simulator has no screen to
    /// record and no broadcast to wait for, so the demo picture takes the place
    /// of the phone's screen and the car's screen shows a picture.
    @MainActor
    func test_AC41_the_car_screen_share_row_starts_the_demo_on_the_simulator() async throws {
        let service = ScreenShareService(relay: ScreenRelayListener(port: Self.relayPort))
        service.startForTheCar()

        #if targetEnvironment(simulator)
        try await waitUntil("the demo took over", timeout: 30) { service.state == .sharing }
        XCTAssertTrue(service.isDemo, "the demo picture did not take the place of the screen")
        #else
        XCTAssertTrue(service.isWaitingForBroadcast, "the row must wait for the broadcast on a device")
        #endif
        service.stop()
        service.stopRelay()
    }

    /// AC42: the encoder can be closed when it never received a frame.
    ///
    /// The writer only starts with the first frame, so a capture that delivers
    /// nothing leaves a writer that was never started — and finishing such a
    /// writer threw an `NSInternalInconsistencyException` that took the app
    /// down. The Simulator does exactly that, and so does a phone that refuses
    /// to record while CarPlay is connected.
    func test_AC42_the_encoder_can_be_closed_without_a_single_frame() async throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")
        let closed = expectation(description: "the writer was closed")
        writer.finish { closed.fulfill() }
        await fulfillment(of: [closed], timeout: 5)
    }

    /// AC43: the relay listens without disturbing a share that is running.
    ///
    /// The relay has to be listening *before* the user picks the broadcast in
    /// the system list, and starting it must not tear down a share that is
    /// already running: the broadcast replaces it when it arrives, not before.
    @MainActor
    func test_AC43_the_relay_does_not_disturb_a_running_share() async throws {
        let service = ScreenShareService(relay: ScreenRelayListener(port: Self.relayPort))
        service.startDemo()
        try await waitUntil("the demo took over", timeout: 30) { service.state == .sharing }
        XCTAssertTrue(service.isDemo)

        service.startRelay()

        XCTAssertTrue(service.isWaitingForBroadcast, "the app is not listening for the broadcast")
        XCTAssertEqual(service.state, .sharing, "the relay stopped the share that was running")
        XCTAssertTrue(service.isDemo, "the demo was stopped before the broadcast arrived")

        service.stop()
        service.stopRelay()
    }

    /// AC44: the broadcast picker points at the app's own extension.
    ///
    /// The picker is given the extension's bundle identifier, and the extension
    /// is the app plus `.ScreenRelay` — so the identifier is derived, never
    /// written down twice.
    func test_AC44_the_broadcast_extension_identifier_follows_the_app() {
        let identifier = ScreenShareService.broadcastExtensionIdentifier
        XCTAssertEqual(identifier, Bundle.main.bundleIdentifier! + ".ScreenRelay")
        XCTAssertFalse(identifier.isEmpty, "the picker would have no extension to offer")
    }

    /// AC50: the app may keep running while the screen is being shared.
    ///
    /// The share to the car happens with the app in the background (the car is
    /// driving the app), and the capture runs in the broadcast extension — so
    /// the app needs the `screen-capture` background mode to stay alive while
    /// the capture runs. `project.yml` is the source of truth for the
    /// Info.plist, so that is what the check reads.
    func test_AC50_the_app_may_run_in_the_background_while_the_screen_is_captured() throws {
        try RepositoryFixture.skipUnlessPresent()
        let text = try String(contentsOf: RepositoryFixture.root.appendingPathComponent("project.yml"), encoding: .utf8)

        XCTAssertTrue(text.contains("\"screen-capture\""),
                      "the app has to keep running while the screen is captured")
        XCTAssertTrue(text.contains("\"audio\""),
                      "the AirPlay route to the car's display needs the audio mode")
    }

    // MARK: - Helpers

    /// AC46: an announcement that arrives in pieces is still taken.
    ///
    /// The extension sends the address in one line, but the network can split
    /// a line in two. A partial read is not a bad address — it is half of one,
    /// and the extension does not send it again, so the app has to wait for
    /// the rest instead of dropping the address for good.
    func test_AC46_an_announcement_that_arrives_in_pieces_is_still_taken() async throws {
        let listener = ScreenRelayListener(port: Self.relayPort)
        let taken = expectation(description: "the announcement was taken")
        var announced: (port: UInt16, token: String)?
        listener.onStream = { port, token in
            announced = (port, token)
            taken.fulfill()
        }
        try listener.start()
        defer { listener.stop() }

        let controlPort = try XCTUnwrap(NWEndpoint.Port(rawValue: Self.relayPort))
        let connection = NWConnection(host: .ipv4(.loopback), port: controlPort, using: .tcp)
        let sent = expectation(description: "both halves were sent")
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            // The address in two pieces, with a gap, the way a network can
            // split it.
            connection.send(content: Data("51234 ".utf8), completion: .contentProcessed { _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    connection.send(content: Data("ab12cd34\n".utf8), completion: .contentProcessed { _ in
                        sent.fulfill()
                    })
                }
            })
        }
        connection.start(queue: DispatchQueue(label: "com.rushabh.cartvv.tests.relay.pieces"))

        await fulfillment(of: [taken, sent], timeout: 10)
        XCTAssertEqual(announced?.port, 51234)
        XCTAssertEqual(announced?.token, "ab12cd34")
    }

    /// AC47: a relay that cannot listen says so, instead of waiting forever.
    ///
    /// The listener binds a port, and the bind fails — a port that is already
    /// taken is the one failure that cannot be talked out of. Without a failure
    /// report the app waits for an announcement that can never arrive, and the
    /// car shows nothing with no reason given.
    @MainActor
    func test_AC47_a_relay_that_cannot_listen_says_so() async throws {
        // A privileged port is not refused on iOS, so the port that is already
        // taken is what makes the bind fail everywhere.
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: Self.takenPort))
        // The blocker listens on the loopback interface, like the app's own
        // relay: a listener on every interface asks a phone for the
        // local-network permission first, and then waits for the answer.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let blocker = try NWListener(using: parameters)
        let taken = expectation(description: "the port is taken")
        blocker.stateUpdateHandler = { state in
            if case .ready = state { taken.fulfill() }
        }
        // A listener without a connection handler never binds: Network.framework
        // logs *"Started without setting either new connection handler or new
        // connection group handler"* and leaves the socket uncreated, so the
        // listener never reaches `.ready`. The handler is what makes the bind
        // happen — the app's own relay sets one for the same reason.
        blocker.newConnectionHandler = { connection in connection.cancel() }
        blocker.start(queue: DispatchQueue(label: "com.rushabh.cartvv.tests.taken"))
        await fulfillment(of: [taken], timeout: 10)

        let service = ScreenShareService(relay: ScreenRelayListener(port: Self.takenPort))
        service.startRelay()

        try await waitUntil("the relay reported the failure") {
            if case .failed = service.state { return true }
            return false
        }
        XCTAssertFalse(service.isWaitingForBroadcast, "the app still waits for a broadcast that cannot come")
        service.stopRelay()
        blocker.cancel()
    }

    /// AC48: the playlist is served correctly while the fragments are written.
    ///
    /// The fragments are filled on the encoder's queue and served on the
    /// server's queue. If they are not filled under the lock they are read
    /// under, a reader can see a half-updated window — and a Swift array that
    /// is mutated while it is read is undefined behaviour, not a glitch.
    func test_AC48_the_playlist_is_served_while_the_fragments_are_written() async throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")

        // The frames keep coming …
        let feeding = Task {
            for index in 0..<300 {
                let buffer = try makePixelBuffer(width: 320, height: 240)
                writer.append(
                    pixelBuffer: buffer,
                    presentationTime: CMTime(value: CMTimeValue(index), timescale: 30)
                )
                try await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        defer { feeding.cancel() }

        // … while the playlist is read over and over.
        var readings = 0
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if let playlist = writer.playlist() {
                readings += 1
                let text = String(decoding: playlist, as: UTF8.self)
                XCTAssertTrue(text.hasPrefix("#EXTM3U"), "a broken playlist: \(text)")
                XCTAssertTrue(text.contains("#EXT-X-MAP"), "no initialisation segment: \(text)")

                // The window is consistent: the media sequence is the index of
                // the first fragment, and the fragments follow one another.
                let indices = text.split(separator: "\n")
                    .compactMap { line -> Int? in
                        guard line.hasPrefix("frag-") else { return nil }
                        return Int(line.dropFirst("frag-".count).dropLast(".m4s".count))
                    }
                XCTAssertFalse(indices.isEmpty, "a playlist without a fragment: \(text)")
                XCTAssertEqual(indices, Array(indices.first!...indices.last!),
                               "the fragment window is torn: \(text)")
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertGreaterThan(readings, 0, "the playlist was never readable while the fragments were written")
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 128, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    /// Waits for a condition — the encoder works on its own queue, so the test
    /// has to keep yielding.
    private func waitUntil(_ description: String, timeout: TimeInterval = 20, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), description)
    }
}
