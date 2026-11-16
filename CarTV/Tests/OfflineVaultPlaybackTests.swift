import AVFoundation
import XCTest
@testable import CarTV

/// The offline vault on the car's display.
///
/// The vault is played by the **phone**: `playOffline` builds a channel and
/// hands it to `PlaybackManager.play(channel:presentation: .fullscreen)`. When a
/// car is connected the picture is offered to it — and the car draws the very
/// frames the phone's player produces.
///
/// A video-only item never renders without an output: CoreMedia logs *"video-only
/// item is waiting for video output"*, the playhead never leaves zero and the
/// car's display stays black while the phone says *"Loading Stream…"*. The
/// phone's own player view is an output only while the phone is in front — so
/// the app has to keep an output of its own while the picture is going to the
/// car.
@MainActor
final class OfflineVaultPlaybackTests: XCTestCase {

    /// AC170: an offline vault video **plays** — the picture advances.
    ///
    /// The car is connected, the way the user had it: the picture is offered to
    /// the car, and the phone keeps playing it until the system says the car
    /// has it.
    func test_AC170_an_offline_vault_video_plays() async throws {
        let file = try await makeVideoFile()
        let manager = PlaybackManager.shared
        // The car is faked for this test — but the flag is put back as it was
        // found, or a **real** car that is connected would be written off.
        let wasConnected = manager.isCarConnected
        manager.isCarConnected = true
        defer {
            manager.isCarConnected = wasConnected
            manager.closePlayer()
        }

        manager.play(channel: Channel(id: UUID(),
                                      name: "AC170",
                                      streamURL: file,
                                      groupTitle: "Offline Vault",
                                      logoURL: nil,
                                      duration: 1),
                     presentation: .fullscreen)

        try await waitUntil("the picture advanced", timeout: 20) {
            manager.currentTime > 0.1
        }
        XCTAssertGreaterThan(manager.currentTime, 0.1, "the picture did not advance")
    }

    /// AC171: a video that is **on its way to the car** keeps an output of the
    /// app's own.
    ///
    /// The car's display is fed by the frames the phone's player produces, and
    /// the phone's own player view cannot be relied on: the CarPlay scene is in
    /// front, so the phone's view is not drawn. Without an output of the app's
    /// own the item waits for one that never comes.
    func test_AC171_a_video_on_its_way_to_the_car_keeps_an_output_of_the_app_s_own() {
        let manager = PlaybackManager()
        let channel = Channel(name: "AC171",
                              streamURL: URL(string: "https://example.com/ac171.m3u8")!)

        manager.play(channel: channel, presentation: .fullscreen)
        manager.handOffToCar()

        XCTAssertTrue(manager.hasVideoOutput,
                      "the car would get no frames: the item waits for an output that never comes")
    }

    /// AC172: a video the **car is waiting for** keeps playing.
    ///
    /// The hand-off ladder offers the picture to the car again and again (the
    /// car's video endpoint appears late), and every offer rebuilds the player
    /// so the system looks at the route again. A rebuild that restarts the
    /// video would leave the picture on the loading card for ever — the phone
    /// says "Loading Stream…" and the car's display stays black.
    func test_AC172_a_video_the_car_is_waiting_for_keeps_playing() async throws {
        let manager = PlaybackManager.shared
        // The car is faked for this test — but the flag is put back as it was
        // found, or a **real** car that is connected would be written off.
        let wasConnected = manager.isCarConnected
        manager.isCarConnected = true
        defer {
            manager.isCarConnected = wasConnected
            manager.closePlayer()
        }

        // The user's own vault file, read only — a test never writes to it.
        let item = try XCTUnwrap(LocalMediaService.shared.localVideos.first,
                                 "the vault holds no video")
        let url = LocalMediaService.shared.getFileURL(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "the vault file is not there: \(url.lastPathComponent)")

        manager.play(channel: Channel(id: UUID(),
                                      name: "AC172",
                                      streamURL: url,
                                      groupTitle: "Offline Vault",
                                      logoURL: nil,
                                      duration: item.duration),
                     presentation: .docked)

        // The timeline of the picture — what the player did, second by second.
        var timeline: [String] = []
        var peak: Double = 0
        /// The picture started over while it was still playing.
        var restarted = false
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let p = manager.player
            let time = manager.currentTime
            // A clip that has **ended** may start again — the car wants to see
            // it. A clip that is still going may not.
            let ended = peak >= manager.duration - 0.5
            if time < peak - 0.5, !ended { restarted = true }
            peak = max(peak, time)
            timeline.append("""
                t=\(String(format: "%.1f", manager.currentTime)) \
                status=\(p?.currentItem?.status.rawValue ?? -1) \
                control=\(p?.timeControlStatus.rawValue ?? -1) \
                rate=\(p?.rate ?? -1) \
                dur=\(manager.duration) \
                offers=\(manager.offerCount)
                """)
        }
        print("AC172 TIMELINE:\n" + timeline.joined(separator: "\n"))

        XCTAssertFalse(restarted,
                       "the picture started over while it was still playing:\n" + timeline.joined(separator: "\n"))
        XCTAssertGreaterThan(peak, 3.0,
                             "the picture never got past the start:\n" + timeline.joined(separator: "\n"))
    }

    /// AC174: the offline vault video reaches the **car's display**.
    ///
    /// The car's display is fed by the frames the phone's player produces, and
    /// the phone's own view cannot be relied on: the CarPlay scene is in
    /// front, so the phone's view is not drawn. The app therefore keeps an
    /// output of its own while the picture is on its way to the car, and the
    /// picture is offered again and again — the car's video endpoint appears a
    /// couple of minutes after the scene connects.
    ///
    /// The proof is the **system's own**: the player says it is playing
    /// externally. A test that forced `isCarConnected` would prove nothing —
    /// the car has to be really there.
    func test_AC174_the_offline_vault_video_reaches_the_car() async throws {
        let manager = PlaybackManager.shared
        defer { manager.closePlayer() }

        // The car has to be really there: the scene delegate says so.
        try await waitUntil("the car did not connect", timeout: 90) {
            manager.isCarConnected
        }

        // The user's own vault file, read only — the very path the user's tap
        // takes.
        let item = try XCTUnwrap(LocalMediaService.shared.localVideos.first,
                                 "the vault holds no video")
        manager.playOffline(item: item)

        // The system's own answer: the picture is on the car's display.
        try await waitUntil("the picture never reached the car's display", timeout: 180) {
            manager.isPlayingOnCar
        }
        XCTAssertTrue(manager.isPlayingOnCar, "the picture never reached the car's display")
        XCTAssertGreaterThan(manager.currentTime, 0.1,
                             "the picture is on the car but nothing was drawn")
    }

    /// AC176: the vault's video is **served over HTTP** — a `file://` URL
    /// inside the app's container cannot be played on the car's route.
    ///
    /// The car's display is fed by the system's own video target — a process
    /// that runs **outside** the app's sandbox. The item then fails with
    /// -11870 (`AVErrorExternalPlaybackNotSupportedForAsset`) the moment the
    /// route takes the picture, and the video dies on the phone *and* on the
    /// car. A loopback URL can be fetched by every process on the phone, so
    /// the same file plays on the car.
    ///
    /// The file is handed to `play(channel:)` — the one way in, which the
    /// vault's own tap, the watch history's "watch again" row and the CarPlay
    /// rows all use.
    func test_AC176_the_vault_video_is_served_over_http() async throws {
        let file = try await makeVideoFile()
        let manager = PlaybackManager()
        defer { manager.closePlayer() }

        manager.play(channel: Channel(id: UUID(),
                                      name: "AC176",
                                      streamURL: file,
                                      groupTitle: "Offline Vault",
                                      logoURL: nil,
                                      duration: 1),
                     presentation: .docked)

        // The **player** was given the URL — that is what the car's video
        // target will fetch.
        let asset = try XCTUnwrap(manager.player?.currentItem?.asset as? AVURLAsset)
        let url = asset.url
        XCTAssertEqual(url.scheme, "http",
                       "the player was given a URL the car's video target cannot fetch")
        XCTAssertFalse(url.isFileURL)

        // The file is really served: the bytes come back as they are on disk.
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, try Data(contentsOf: file))

        // And a range request gets the slice that was asked for: the player
        // seeks, and the car's video target asks for the bytes it wants.
        var request = URLRequest(url: url)
        request.setValue("bytes=0-99", forHTTPHeaderField: "Range")
        let (slice, rangeResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((rangeResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(slice, try Data(contentsOf: file).prefix(100))
    }

    // MARK: - The file

    /// A one-second video in a temporary directory.
    ///
    /// The vault's own file is the user's data — a test must not touch it (see
    /// `LocalMediaService(storageDirectory:)`), so the test writes its own.
    private func makeVideoFile() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AC170-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for index in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                XCTFail("the writer has no pixel buffers")
                return url
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else {
                XCTFail("the pixel buffer could not be made")
                return url
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0x40, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30))
        }
        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        XCTAssertEqual(writer.status, .completed, "the test video could not be written")
        return url
    }

    /// Waits for a condition — the player works on its own queue, so the test
    /// has to keep yielding.
    private func waitUntil(_ description: String, timeout: TimeInterval = 20, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), description)
    }
}
