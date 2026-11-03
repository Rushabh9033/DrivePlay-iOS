import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Network

/// The parts of the screen-share chain that the app **and** the broadcast
/// extension both need: the encoder that turns frames into HLS fragments, the
/// server that serves them, and the address the two processes use to find
/// each other.
///
/// The extension runs in its own process, so nothing can be shared at run time
/// — the code is compiled into both targets instead.
///
/// The chain itself:
///
///     frames → H.264 fragments → a local HTTP server → the app's AVPlayer
///
/// The app plays the very stream it serves, and that is what puts the phone's
/// screen on the car's display.

// MARK: - Writer

/// Encodes the captured screen into HLS fragments (fragmented MP4).
///
/// `AVAssetWriter` in segment mode hands the finished fragments to its delegate
/// instead of writing a file: an initialisation segment (`moov`) first, then one
/// `moof`+`mdat` fragment per second. That is exactly what a live HLS playlist
/// over HTTP needs, and `AVPlayer` — the player CarPlay draws — reads it.
final class LiveScreenWriter: NSObject, AVAssetWriterDelegate {

    struct Fragment {
        let index: Int
        let duration: Double
        let data: Data
    }

    private let writer: AVAssetWriter
    private let queue = DispatchQueue(label: "com.rushabh.cartvv.screenshare.writer")
    /// Guards every piece of state the HTTP server reads.
    ///
    /// The writer fills the fragments on its own queue while the server serves
    /// them on another, so the state is read and written under the **same**
    /// lock — a lock that only the readers take protects nothing, and a Swift
    /// array mutated while it is read is undefined behaviour.
    private let lock = NSLock()
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private var initialisation: Data?
    private var fragments: [Fragment] = []
    private var nextIndex = 0
    private var ready = false
    private var readyCallback: (() -> Void)?

    /// Called once, when there is something to serve.
    var onReady: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return readyCallback }
        set { lock.lock(); readyCallback = newValue; lock.unlock() }
    }

    /// How many fragments are kept. The playlist lists fewer than this, so a
    /// player that is a little behind the live edge still finds the segment it
    /// asks for — a 404 kills the player item for good, and AVFoundation never
    /// retries.
    private let storedFragments = 30
    /// How many fragments the playlist lists.
    private let advertisedFragments = 10

    private init(writer: AVAssetWriter) {
        self.writer = writer
        super.init()
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        writer.delegate = self
    }

    /// The encoder, or nil when it cannot be set up.
    static func make() -> LiveScreenWriter? {
        guard let writer = try? AVAssetWriter(contentType: .mpeg4Movie) else { return nil }
        return LiveScreenWriter(writer: writer)
    }

    // MARK: Frames

    /// Adds one captured frame. Safe to call from any thread.
    func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        queue.async { [weak self] in
            self?.appendOnQueue(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
        }
    }

    private func appendOnQueue(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        if !sessionStarted {
            guard let input = Self.makeInput(for: pixelBuffer) else { return }
            self.input = input
            guard writer.canAdd(input) else { return }
            writer.add(input)
            // The segment output needs a numeric origin: without it the writer
            // refuses every frame with AVFoundation error -11875.
            writer.initialSegmentStartTime = presentationTime
            do {
                try writer.startWriting()
            } catch {
                NSLog("DRIVEPLAY screen share: cannot start the writer: %@", error.localizedDescription)
                return
            }
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }
        guard let input, input.isReadyForMoreMediaData else { return }
        guard let sample = Self.makeSampleBuffer(pixelBuffer: pixelBuffer, presentationTime: presentationTime) else { return }
        if !input.append(sample) {
            NSLog("DRIVEPLAY screen share: a frame could not be appended")
        }
    }

    private static func makeInput(for pixelBuffer: CVPixelBuffer) -> AVAssetWriterInput? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let format = formatDescription else { return nil }

        let size = CMVideoFormatDescriptionGetDimensions(format)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_500_000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ],
            sourceFormatHint: format
        )
        input.expectsMediaDataInRealTime = true
        return input
    }

    private static func makeSampleBuffer(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let format = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let buffer = sampleBuffer else { return nil }
        return buffer
    }

    // MARK: Fragments

    func assetWriter(
        _ assetWriter: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        let seconds = segmentReport?.trackReports.first?.duration.seconds ?? 1
        // An invalid time has no seconds, and `Int(Double.nan)` traps — which
        // would take the app (or the broadcast extension) down. The duration is
        // made safe here, once, where it is read.
        let duration = seconds.isFinite && seconds > 0 ? seconds : 1
        queue.async { [weak self] in
            guard let self else { return }
            // The fragments are served by the HTTP server on another thread, so
            // they are filled under the same lock they are read under.
            self.lock.lock()
            switch segmentType {
            case .initialization:
                self.initialisation = segmentData
            case .separable:
                self.fragments.append(Fragment(index: self.nextIndex, duration: duration, data: segmentData))
                self.nextIndex += 1
                if self.fragments.count > self.storedFragments {
                    self.fragments.removeFirst(self.fragments.count - self.storedFragments)
                }
            @unknown default:
                break
            }
            let becameReady = !self.ready && self.initialisation != nil && !self.fragments.isEmpty
            if becameReady { self.ready = true }
            let onReady = self.readyCallback
            self.lock.unlock()

            if becameReady {
                DispatchQueue.main.async { onReady?() }
            }
        }
    }

    /// The fragments in the window, read under the lock.
    var currentFragments: [Fragment] {
        lock.lock()
        defer { lock.unlock() }
        return fragments
    }

    /// The live playlist. It is built on every request: a live playlist must not
    /// be cached and it changes as the window slides.
    ///
    /// The segment names are relative to the playlist's own folder — the
    /// playlist is served from `/<token>/`, so `init.mp4` resolves to
    /// `/<token>/init.mp4`. The token is enforced by the request path.
    func playlist() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let initialisation, !fragments.isEmpty else { return nil }
        // The playlist lists the newest fragments; the older ones are kept so
        // that a player which is a little behind still finds what it asks for.
        let listed = Array(fragments.suffix(advertisedFragments))
        let target = max(1, Int((listed.map { $0.duration }.max() ?? 1).rounded(.up)))
        var text = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:\(target)
        #EXT-X-MEDIA-SEQUENCE:\(listed[0].index)
        #EXT-X-MAP:URI="init.mp4"

        """
        for fragment in listed {
            text += "#EXTINF:\(String(format: "%.3f", fragment.duration)),\nfrag-\(fragment.index).m4s\n"
        }
        return Data(text.utf8)
    }

    func initialisationSegment() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return initialisation
    }

    func fragment(index: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return fragments.first { $0.index == index }?.data
    }

    /// Closes the writer. The fragments written so far stay valid.
    ///
    /// The completion runs when the writer is closed — or when it was never
    /// open, which is the case when not a single frame ever arrived.
    func finish(completion: (() -> Void)? = nil) {
        // The writer is captured **strongly**: the owner drops it right after
        // this call, and a weak capture would let it die before the queued
        // block runs — the encoder would never be finished and the last
        // fragment would never be flushed.
        queue.async { [self] in
            // A writer that never started cannot be finished: AVFoundation throws
            // an NSInternalInconsistencyException, which takes the app down. That
            // is the normal case when the capture delivers no frame at all — the
            // Simulator, or a phone that refuses to record while CarPlay is
            // connected.
            guard writer.status == .writing else {
                completion?()
                return
            }
            input?.markAsFinished()
            let assetWriter = writer
            assetWriter.finishWriting { completion?() }
        }
    }
}

// MARK: - Server

/// Serves the playlist, its fragments and a small player page over HTTP.
///
/// Every path carries a random token: the stream is the phone's screen, so it
/// must not be readable by whatever else is on the network.
final class ScreenStreamServer {

    let token = String(UUID().uuidString.prefix(8))

    private let writer: LiveScreenWriter
    private let queue = DispatchQueue(label: "com.rushabh.cartvv.screenshare.server")
    private var listener: NWListener?

    init(writer: LiveScreenWriter) {
        self.writer = writer
    }

    /// Starts listening. `ready` is called with the port once it is bound.
    func start(ready: @escaping (UInt16) -> Void) throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, let port = self.listener?.port else { return }
            ready(port.rawValue)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Requests

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()

        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
                guard let self, let data, error == nil else {
                    connection.cancel()
                    return
                }
                buffer.append(data)
                // A request that never ends must not eat the memory: the
                // server is reachable from the whole local network.
                guard buffer.count <= 16 * 1024 else {
                    connection.cancel()
                    return
                }
                guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    pump()
                    return
                }
                let request = String(decoding: buffer[buffer.startIndex..<end.upperBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self.respond(to: path, on: connection) { pump() }
            }
        }
        pump()
    }

    private func respond(to rawPath: String, on connection: NWConnection, then: @escaping () -> Void) {
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        let prefix = "/\(token)"

        guard path.hasPrefix(prefix) else {
            send(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8), on: connection, then: then)
            return
        }

        switch String(path.dropFirst(prefix.count)) {
        case "/live.m3u8":
            guard let playlist = writer.playlist() else {
                send(status: "503 Service Unavailable", type: "text/plain", body: Data("The stream is not ready".utf8), on: connection, then: then)
                return
            }
            send(status: "200 OK", type: "application/vnd.apple.mpegurl", body: playlist, on: connection, then: then)
        case "/init.mp4":
            guard let data = writer.initialisationSegment() else {
                send(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8), on: connection, then: then)
                return
            }
            send(status: "200 OK", type: "video/mp4", body: data, on: connection, then: then)
        case "/":
            send(status: "200 OK", type: "text/html; charset=utf-8", body: Data(Self.page.utf8), on: connection, then: then)
        default:
            let resource = String(path.dropFirst(prefix.count))
            if resource.hasPrefix("/frag-"), resource.hasSuffix(".m4s"),
               let index = Int(resource.dropFirst("/frag-".count).dropLast(".m4s".count)),
               let data = writer.fragment(index: index) {
                send(status: "200 OK", type: "video/mp4", body: data, on: connection, then: then)
            } else {
                send(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8), on: connection, then: then)
            }
        }
    }

    private func send(status: String, type: String, body: Data, on connection: NWConnection, then: @escaping () -> Void) {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        \r

        """
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.send(content: body, completion: .contentProcessed { _ in
                then()
            })
        })
    }

    /// A player page, so any browser on the network can watch the screen.
    private static let page = """
    <!doctype html><html><head><meta charset="utf-8">
    <title>DrivePlay — screen share</title>
    <style>html,body{background:#000;margin:0;height:100%}
    video{width:100vw;height:100vh;object-fit:contain}</style></head>
    <body><video src="live.m3u8" controls autoplay muted playsinline></video></body></html>
    """
}

// MARK: - Frames

/// Draws a captured frame onto the canvas the encoder takes.
///
/// The encoder cannot scale: the output size has to match the frames, and the
/// size of an `AVAssetWriterInput` cannot change while it is writing — a
/// frame of another size is dropped, and a rotated phone would freeze the
/// stream for good. So every frame is drawn onto the **same** canvas: scaled
/// to fit, centred, with black around it.
enum ScreenFrameScaler {

    /// The canvas every picture is drawn on. A car's screen is landscape, so
    /// the canvas is too; a portrait phone gets bars on the sides.
    static let canvas = CGSize(width: 1280, height: 720)

    static func scale(_ source: CVPixelBuffer, context: CIContext) -> CVPixelBuffer? {
        fit(CIImage(cvPixelBuffer: source), context: context)
    }

    /// Draws the picture onto the canvas, scaled to fit and centred.
    static func fit(_ image: CIImage, context: CIContext) -> CVPixelBuffer? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let factor = min(canvas.width / extent.width, canvas.height / extent.height)
        let width = extent.width * factor
        let height = extent.height * factor

        var scaled: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(canvas.width),
            Int(canvas.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &scaled
        ) == noErr, let scaled else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(origin: .zero, size: canvas)
        // The bars around the picture are black.
        context.render(
            CIImage(color: CIColor.black).cropped(to: bounds),
            to: scaled,
            bounds: bounds,
            colorSpace: colorSpace
        )
        context.render(
            image.transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
            to: scaled,
            bounds: CGRect(
                x: (canvas.width - width) / 2,
                y: (canvas.height - height) / 2,
                width: width,
                height: height
            ),
            colorSpace: colorSpace
        )
        return scaled
    }
}

// MARK: - Relay channel

/// The address the app and the broadcast extension use to find each other.
///
/// The extension encodes the screen and serves it; it cannot hand the address of
/// that server to the app any other way — the two live in different processes
/// and share no container (an App Group would need another Apple-granted
/// capability). So the extension opens a connection to the app's fixed loopback
/// port and sends the address in one line.
enum ScreenRelayEndpoint {

    /// The port the app listens on. It is bound to the loopback interface, so
    /// nothing outside the phone can reach it — the announcement carries the
    /// token that unlocks the screen stream.
    static let port: UInt16 = 47311

    /// The address of the extension's stream: `<port> <token>`.
    static func announcement(port: UInt16, token: String) -> String {
        "\(port) \(token)\n"
    }

    /// The address the extension announced, if the line is one.
    static func parse(_ line: String) -> (port: UInt16, token: String)? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard parts.count == 2, let port = UInt16(parts[0]), !parts[1].isEmpty else { return nil }
        return (port, parts[1])
    }
}
