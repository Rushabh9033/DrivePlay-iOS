import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Network
import ReplayKit
import UIKit
import UniformTypeIdentifiers
#if canImport(Shared)
import Shared
#endif

/// Live screen sharing: the phone's screen, sent to the car as a video stream.
///
/// CarPlay never shows a mirror — a car screen can only show the video the app
/// is playing. So the chain is:
///
///     ReplayKit capture → H.264 fragments → a local HTTP server → the app's AVPlayer
///
/// The app plays the very stream it serves, and that is what puts the phone's
/// screen on the car's display. The same playlist is served on the local network,
/// so a screen that is not this phone (a head unit with a browser, VLC) can watch
/// it too.
///
/// `RPScreenRecorder` is deprecated in iOS 27 in favour of ScreenCaptureKit's
/// `SCStream`, but ScreenCaptureKit only exists from iOS 27 and this app still
/// supports iOS 18 — so ReplayKit is the capture that works today.
public enum ScreenShareState: Equatable {
    case idle
    case starting
    case sharing
    case failed(String)

    /// True while there is a share to end.
    ///
    /// `ScreenShareService.stop()` refuses to run when nothing is being
    /// shared, so a "stop" row may only be offered while this is true.
    public var isRunning: Bool {
        switch self {
        case .starting, .sharing: return true
        case .idle, .failed: return false
        }
    }
}

// MARK: - Demo source

/// Draws a synthetic picture and feeds it to the encoder.
///
/// The CarPlay Simulator has no capturable screen, so this is the only way to
/// see the whole chain — encode, serve, play — working there. On a real iPhone
/// the screen capture replaces it.
final class DemoFrameSource {

    private static let size = ScreenFrameScaler.canvas
    private static let renderer = UIGraphicsImageRenderer(size: size)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private let queue = DispatchQueue(label: "com.rushabh.cartvv.screenshare.demo")
    private let lock = NSLock()
    private var running = true

    /// Feeds 30 frames a second until the source is stopped.
    func start(writer: LiveScreenWriter) {
        queue.async { [weak self] in
            guard let self else { return }
            var frame = 0
            while self.isRunning {
                if let buffer = Self.drawFrame(index: frame) {
                    writer.append(
                        pixelBuffer: buffer,
                        presentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
                    )
                }
                frame += 1
                Thread.sleep(forTimeInterval: 1.0 / 30.0)
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private static func drawFrame(index: Int) -> CVPixelBuffer? {
        let image = renderer.image { context in
            UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // A bar that travels, so the picture really moves.
            UIColor(red: 0.10, green: 1, blue: 0.53, alpha: 1).setFill()
            let x = CGFloat(index * 6).truncatingRemainder(dividingBy: size.width + 160) - 80
            context.fill(CGRect(x: x, y: 0, width: 80, height: size.height))
            "DrivePlay\ndemo stream\nframe \(index)".draw(
                in: CGRect(x: 60, y: 480, width: size.width - 120, height: 400),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 64),
                    .foregroundColor: UIColor.white
                ]
            )
        }

        guard let picture = CIImage(image: image) else { return nil }
        // The scaler makes the buffer, so the demo picture is encoded exactly
        // like a captured frame — same canvas, same pixel format, same
        // IOSurface-backed allocation.
        return ScreenFrameScaler.fit(picture, context: context)
    }
}

// MARK: - Service

/// Owns the screen capture, the encoder and the server — one capture, one stream.
@MainActor
public final class ScreenShareService: ObservableObject {

    public static let shared = ScreenShareService()

    /// The bundle identifier of the extension that broadcasts the screen.
    ///
    /// The extension is the app plus `.ScreenRelay`, so the identifier is
    /// derived from the app's own — the two can never drift apart.
    nonisolated public static let broadcastExtensionIdentifier =
        (Bundle.main.bundleIdentifier ?? "") + ".ScreenRelay"

    @Published public private(set) var state: ScreenShareState = .idle
    /// True while the app waits for a broadcast of the phone's screen.
    ///
    /// The relay only listens — it shares nothing until the broadcast
    /// extension announces its stream. It therefore does not latch the share
    /// state: a capture or the demo picture can still be started while it waits.
    @Published public private(set) var isWaitingForBroadcast = false
    /// The page the **car** asked for, waiting to be sent.
    ///
    /// CarPlay has no web view of its own, so a page the user opens on the car
    /// runs on the phone and reaches the car through the phone's screen share.
    /// iOS always asks the **user** to start a share, so the phone has to say
    /// that the car is waiting — this is that note, and it is cleared as soon
    /// as the broadcast arrives.
    @Published public private(set) var pendingCarPage: String?
    /// The playlist the app itself plays, on the loopback interface.
    @Published public private(set) var playlistURL: URL?
    /// The same playlist on the local network, for a screen that is not this phone.
    @Published public private(set) var networkPlaylistURL: URL?

    /// True while the demo picture is being shared instead of the real screen —
    /// this device cannot record it.
    public var isDemo: Bool { demo != nil }

    private var writer: LiveScreenWriter?
    private var server: ScreenStreamServer?
    private var demo: DemoFrameSource?
    /// The channel the broadcast extension announces its stream on.
    private let relay: ScreenRelayListener
    private var port: UInt16?
    private var isCapturing = false
    private var isStopping = false
    /// The frame counter is touched by the capture's callback, which runs on
    /// ReplayKit's own thread — it is not main-actor state.
    private nonisolated(unsafe) let frameLock = NSLock()
    private nonisolated(unsafe) var deliveredFrames = false
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// Starts the screen capture.
    ///
    /// A closure so the failure path can be tested: a capture that ends
    /// without a frame has to hand over to the demo picture instead of dying.
    /// On a real phone ReplayKit waits for the user's consent and never ends
    /// on its own, so the real capture cannot produce that case in a test.
    typealias CaptureStarter = (
        _ onFrame: @escaping (CMSampleBuffer) -> Void,
        _ onEnd: @escaping @Sendable (Error?) -> Void
    ) -> Void

    private let startCapture: CaptureStarter

    /// The relay is a parameter so the failure path can be tested: a listener
    /// that cannot bind has to say so instead of waiting forever.
    init(relay: ScreenRelayListener = ScreenRelayListener(),
         capture: @escaping CaptureStarter = ScreenShareService.replayKitCapture) {
        self.relay = relay
        self.startCapture = capture
    }

    /// The real capture: ReplayKit.
    private nonisolated static func replayKitCapture(onFrame: @escaping (CMSampleBuffer) -> Void,
                                                      onEnd: @escaping @Sendable (Error?) -> Void) {
        RPScreenRecorder.shared().startCapture(
            handler: { sampleBuffer, bufferType, error in
                guard error == nil, bufferType == .video else { return }
                onFrame(sampleBuffer)
            },
            completionHandler: onEnd
        )
    }

    // MARK: Start and stop

    public func start() {
        start(captureAvailable: RPScreenRecorder.shared().isAvailable)
    }

    /// The availability check is a parameter so the failure path can be tested
    /// on a device that can record.
    func start(captureAvailable: Bool) {
        // A failed share may be started again; a running one may not.
        switch state {
        case .idle, .failed: break
        default: return
        }

        guard captureAvailable else {
            state = .failed("This device cannot record the screen. Run the app on a real iPhone.")
            return
        }
        guard let writer = prepare() else { return }

        isCapturing = true
        // The capture's callback runs on ReplayKit's own thread, so the writer
        // and the context are taken here — nothing that belongs to the main
        // actor may be touched there.
        let context = self.context
        startCapture(
            { [weak self] sampleBuffer in
                Self.consume(sampleBuffer, into: writer, context: context)
                self?.markFrameDelivered()
            },
            { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    // A newer share may have taken over in the meantime — the
                    // broadcast replaces the capture. The callback of a capture
                    // that was stopped must not tear the new share down.
                    guard self.writer === writer else { return }
                    if let error {
                        NSLog("DRIVEPLAY screen share stopped: %@", error.localizedDescription)
                        self.state = .failed(Self.message(for: error))
                        self.tearDown()
                        return
                    }
                    if self.isStopping {
                        self.tearDown()
                        return
                    }
                    if self.hasDeliveredFrames() {
                        // The capture ended by itself. Say why, instead of going quiet.
                        self.state = .failed("The screen recording stopped.")
                        self.tearDown()
                        return
                    }
                    // This device has no screen to record — the Simulator, or a
                    // device without a capturable display. The chain is the same,
                    // only the source differs, so the demo picture takes over and
                    // the share keeps working.
                    self.tearDown()
                    self.startDemo()
                }
            }
        )
    }

    /// Feeds a drawn picture through the same encoder and server.
    ///
    /// The CarPlay Simulator has no screen to capture, so this is the only way
    /// to see the whole chain working there.
    public func startDemo() {
        switch state {
        case .idle, .failed: break
        default: return
        }
        guard let writer = prepare() else { return }
        let demo = DemoFrameSource()
        self.demo = demo
        demo.start(writer: writer)
    }

    /// Starts the share the car's screen-share row asks for.
    ///
    /// The row cannot record the screen: iOS refuses to record while CarPlay is
    /// connected (`RPRecordingErrorCarPlay`). So the row waits for a broadcast —
    /// except on the Simulator, where there is no screen to record and no
    /// broadcast to wait for, and the demo picture takes the place of the
    /// phone's screen. On a real car the row waits: a fake picture would be
    /// worse than nothing.
    public func startForTheCar() {
        startRelay()
        if Self.startsDemoInsteadOfBroadcast { startDemo() }
    }

    /// The car asked for a page address.
    ///
    /// Browser navigation is independent from screen sharing: car requests do
    /// not secretly trigger screen recording or broadcast relays.
    public func carRequestedPage(_ address: String) {
        pendingCarPage = address
    }

    /// True on the Simulator, where the demo picture stands in for the screen.
    ///
    /// It is a build-time fact, not a guess at run time: the Simulator has no
    /// capturable screen and no broadcast to start, and a real phone has both.
    public static var startsDemoInsteadOfBroadcast: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Waits for a broadcast of the phone's screen and plays it.
    ///
    /// The car's own row cannot record the screen: iOS refuses to record while
    /// CarPlay is connected (`RPRecordingErrorCarPlay`, "Failed to start
    /// recording due to carplay being active"). A broadcast — the same thing
    /// WhatsApp uses for a screen share — is started by the user from the
    /// Control Center, and this is where its stream arrives.
    public func startRelay() {
        // The relay only **listens**. It shares nothing until the broadcast
        // extension announces its stream, and a share that is already running is
        // replaced *then* — not now. Stopping it here would break the very thing
        // the relay is for: a broadcast that starts while a share runs.
        isStopping = false

        relay.onStream = { [weak self] port, token in
            Task { @MainActor in self?.playRelay(port: port, token: token) }
        }
        relay.onFailure = { [weak self] error in
            Task { @MainActor in
                self?.isWaitingForBroadcast = false
                // A running share is not disturbed by a relay that cannot start.
                if self?.state != .sharing {
                    self?.state = .failed("The screen relay could not start: \(error.localizedDescription)")
                }
            }
        }
        do {
            try relay.start()
            isWaitingForBroadcast = true
            // The relay is up, so an earlier failure is over.
            if case .failed = state { state = .idle }
        } catch {
            // A running share is not disturbed by a relay that cannot start.
            isWaitingForBroadcast = false
            if case .sharing = state { } else {
                state = .failed("The screen relay could not start: \(error.localizedDescription)")
            }
        }
    }

    /// Stops listening for a broadcast — the car disconnected.
    public func stopRelay() {
        relay.stop()
        isWaitingForBroadcast = false
    }

    /// Plays the stream the broadcast extension serves.
    ///
    /// The extension announces the stream only when there is something to play,
    /// so the player never sees the "503 not ready" — AVFoundation fails a
    /// player item for good when it sees one.
    private func playRelay(port: UInt16, token: String) {
        // The broadcast's stream replaces whatever was being shared.
        if demo != nil || isCapturing { stop() }
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(token)/live.m3u8") else { return }
        isWaitingForBroadcast = false
        // The share is running, so the car is no longer waiting for one.
        pendingCarPage = nil
        playlistURL = url
        state = .sharing
        // The car's screen shows what the app plays — so the app plays the stream.
        PlaybackManager.shared.playScreenShare(url: url, title: "iPhone screen")
    }

    public func stop() {
        guard state == .starting || state == .sharing else { return }
        isStopping = true
        if isCapturing {
            RPScreenRecorder.shared().stopCapture { error in
                if let error { NSLog("DRIVEPLAY stopCapture error: %@", error.localizedDescription) }
            }
        }
        tearDown()
    }

    /// Sets the encoder and the server up. Returns nil and sets the failure.
    private func prepare() -> LiveScreenWriter? {
        guard let writer = LiveScreenWriter.make() else {
            state = .failed("The video encoder could not start.")
            return nil
        }
        let server = ScreenStreamServer(writer: writer)
        self.writer = writer
        self.server = server
        state = .starting
        isStopping = false
        frameLock.lock()
        deliveredFrames = false
        frameLock.unlock()

        writer.onReady = { [weak self] in
            Task { @MainActor in self?.publish() }
        }
        do {
            try server.start { [weak self] port in
                Task { @MainActor in
                    self?.port = port
                    self?.publish()
                }
            }
        } catch {
            state = .failed("The stream server could not start: \(error.localizedDescription)")
            return nil
        }
        return writer
    }

    private func tearDown() {
        demo?.stop()
        demo = nil
        writer?.finish()
        writer = nil
        server?.stop()
        server = nil
        // The relay keeps listening: the car is still connected, so the next
        // broadcast has to be picked up. It stops when the car disconnects.
        port = nil
        isCapturing = false
        playlistURL = nil
        networkPlaylistURL = nil
        if case .failed = state { } else { state = .idle }
        PlaybackManager.shared.stopScreenShare()
    }

    // MARK: Frames

    private nonisolated func markFrameDelivered() {
        frameLock.lock()
        deliveredFrames = true
        frameLock.unlock()
    }

    private nonisolated func hasDeliveredFrames() -> Bool {
        frameLock.lock()
        defer { frameLock.unlock() }
        return deliveredFrames
    }

    /// The reason a capture failed, in words the driver can act on.
    ///
    /// iOS refuses to record the screen while CarPlay is connected — the error
    /// reads "Failed to start recording due to carplay being active", which
    /// means the share has to come from a broadcast instead.
    private static func message(for error: Error) -> String {
        if (error as NSError).code == RPRecordingErrorCode.carPlay.rawValue {
            return "iOS does not allow recording the screen while CarPlay is connected. "
                + "Start a DrivePlay broadcast from the Control Center instead."
        }
        return error.localizedDescription
    }

    // MARK: Publishing

    private func publish() {
        guard let port, let server, writer?.playlist() != nil else { return }
        let path = "\(server.token)/live.m3u8"
        playlistURL = URL(string: "http://127.0.0.1:\(port)/\(path)")
        if let address = LocalNetworkAddress.ipv4() {
            networkPlaylistURL = URL(string: "http://\(address):\(port)/\(path)")
        }
        state = .sharing
        // The car's screen shows what the app plays — so the app plays the stream.
        if let playlistURL {
            PlaybackManager.shared.playScreenShare(
                url: playlistURL,
                title: demo == nil ? "iPhone screen" : "DrivePlay demo"
            )
        }
    }

    // MARK: Frames

    private static func consume(_ sampleBuffer: CMSampleBuffer, into writer: LiveScreenWriter, context: CIContext) {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let scaled = ScreenFrameScaler.scale(source, context: context) else { return }
        writer.append(pixelBuffer: scaled, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

}

// MARK: - Local address

/// The device's address on the local network, so another screen can be given a
/// link it can actually open.
enum LocalNetworkAddress {
    static func ipv4() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var found: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            found = String(cString: host)
            break
        }
        return found
    }
}
