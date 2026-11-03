import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Network
import ReplayKit

/// The broadcast upload extension: the phone's screen, as a live stream.
///
/// This is the capture that works **while CarPlay is connected**. ReplayKit
/// refuses to record the screen while the car is active
/// (`RPRecordingErrorCarPlay`), so the car's own "Screen Mirroring" row can
/// never record anything. A broadcast — the same mechanism WhatsApp uses for a
/// screen share — is started by the user and keeps working.
///
/// The extension encodes the frames and serves the stream, then tells the app
/// where the stream is. The app plays it, and a car screen shows what the app
/// plays — that is what puts the phone's screen on the car's display.
public class SampleHandler: RPBroadcastSampleHandler {

    private let queue = DispatchQueue(label: "com.rushabh.cartvv.screenrelay")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var writer: LiveScreenWriter?
    private var server: ScreenStreamServer?
    private var port: UInt16?
    private var announced = false

    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // A second broadcast in the same process has to be announced again —
        // the latch of the first one would keep the app from ever hearing it.
        queue.async { [weak self] in
            self?.announced = false
            self?.port = nil
        }

        guard let writer = LiveScreenWriter.make() else {
            finishBroadcastWithError(NSError(
                domain: "com.rushabh.cartvv.screenrelay",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The video encoder could not start."]
            ))
            return
        }
        self.writer = writer

        // The stream is announced as soon as there is something to play: the app
        // must never see a "503 not ready" — AVFoundation fails a player item
        // for good when it sees one.
        writer.onReady = { [weak self] in
            self?.announce()
        }

        let server = ScreenStreamServer(writer: writer)
        self.server = server
        do {
            try server.start { [weak self] boundPort in
                guard let self else { return }
                // The port is written on the server's own queue and read on
                // this one — it is only ever touched on `queue`.
                self.queue.async {
                    self.port = boundPort
                    self.announceNow()
                }
            }
        } catch {
            finishBroadcastWithError(NSError(
                domain: "com.rushabh.cartvv.screenrelay",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The stream server could not start: \(error.localizedDescription)"]
            ))
        }
    }

    public override func broadcastPaused() {}

    public override func broadcastResumed() {}

    public override func broadcastFinished() {
        writer?.finish()
        writer = nil
        server?.stop()
        server = nil
        queue.async { [weak self] in
            self?.port = nil
            self?.announced = false
        }
    }

    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let scaled = ScreenFrameScaler.scale(source, context: context) else { return }
        writer?.append(
            pixelBuffer: scaled,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
    }

    // MARK: - Telling the app where the stream is

    /// Announces the stream to the app.
    ///
    /// The app listens on a fixed loopback port. The user starts the broadcast
    /// from the Control Center, so the app may not be listening yet — the
    /// announcement is repeated until the app takes it.
    private func announce() {
        // The bookkeeping runs on `queue`, so the port and the latch are only
        // ever touched there.
        queue.async { [weak self] in self?.announceNow() }
    }

    private func announceNow() {
        guard !announced, let port, let token = server?.token else { return }
        announced = true
        send(port: port, token: token, attempt: 0)
    }

    private func send(port: UInt16, token: String, attempt: Int) {
        guard let controlPort = NWEndpoint.Port(rawValue: ScreenRelayEndpoint.port) else { return }
        let connection = NWConnection(host: .ipv4(.loopback), port: controlPort, using: .tcp)
        let line = ScreenRelayEndpoint.announcement(port: port, token: token)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                connection.send(content: Data(line.utf8), completion: .contentProcessed { error in
                    if let error {
                        NSLog("DRIVEPLAY screen relay: the announcement failed: %@", error.localizedDescription)
                        connection.cancel()
                        self?.retry(port: port, token: token, attempt: attempt)
                    } else {
                        connection.cancel()
                    }
                })
            case .failed(let error):
                NSLog("DRIVEPLAY screen relay: the app is not listening yet: %@", error.localizedDescription)
                connection.cancel()
                self?.retry(port: port, token: token, attempt: attempt)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// The app starts listening when the user picks the share on the car, so
    /// the first attempts can fail. Keep trying for a few minutes.
    private func retry(port: UInt16, token: String, attempt: Int) {
        let limit = 150
        guard attempt < limit else {
            NSLog("DRIVEPLAY screen relay: no app took the announcement")
            return
        }
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.send(port: port, token: token, attempt: attempt + 1)
        }
    }
}
