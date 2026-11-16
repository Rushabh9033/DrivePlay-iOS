import AVFoundation
import Combine
import CoreImage
import CoreMedia
import Foundation
import os
import WebKit

/// The browser's own log.
///
/// `os_log`, not `NSLog`: an `NSLog` line goes to the process's **stderr** and
/// never reaches the device's unified log, so the car's own log said nothing
/// about the picture. An `os_log` line is in the device log like any other.
let carBrowserLog = Logger(subsystem: "com.rushabh.cartvv", category: "CarBrowser")

/// The browser that runs **on the car's display**.
///
/// CarPlay cannot draw a web page: there is no web template in
/// `CarPlay.framework` at all. What the car *can* draw is the video the app
/// plays, so the browser on the car is the app's **own** web view, drawn into
/// the same chain the TV channels use —
///
///     the web view → a picture → the encoder → a local HTTP server → the app's AVPlayer
///
/// The app plays the very stream it serves, and the car draws that. So the
/// Browser tab is no longer a remote control for the phone: the page runs in
/// the app, on the car's own display, and the car's rows drive it.
///
/// The web view is **not in a window**. Measured on the device: a web view
/// with no window at all keeps rendering — five of five pictures carried the
/// page — and its layout viewport is exactly the 1280×720 of the car's
/// screen, while a web view in a window loses the safe area and lays out at
/// 1280×639.
@MainActor
public final class CarBrowserStream: ObservableObject {

    /// The one the app uses.
    public static let shared = CarBrowserStream()

    /// The picture the car shows — the canvas of the encoder and the layout
    /// viewport of the web view. A car's screen is landscape, and 16:9 is what
    /// it has.
    public static let viewport = CGSize(width: 1280, height: 720)

    /// The address on the car's display.
    @Published public private(set) var address: String = ""
    /// True while the picture is on its way to the car.
    @Published public private(set) var isRunning: Bool = false
    /// True while the page can go back.
    @Published public private(set) var canGoBack: Bool = false
    /// True while the page can go forward.
    @Published public private(set) var canGoForward: Bool = false
    /// The playlist the app plays — the picture the car draws.
    @Published public private(set) var playlistURL: URL?

    /// The web view the car looks at.
    ///
    /// Internal, so the test can measure what the car would see.
    let webView: WKWebView
    /// The delegate is **weak** — the app has to hold it, or the page's
    /// address is never heard about.
    private let delegate = NavigationDelegate()

    private var writer: LiveScreenWriter?
    private var server: ScreenStreamServer?
    private var port: UInt16?
    private var captureTask: Task<Void, Never>?
    /// The number of pictures that went to the encoder — the stream's clock.
    private(set) var framesSent: Int64 = 0
    /// The last picture that went to the encoder.
    ///
    /// The picture is the only thing the car ever sees, so a test that
    /// measured the web view instead would be measuring something the car
    /// does not look at.
    private(set) var lastFrame: CVPixelBuffer?
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// How often the page is captured.
    ///
    /// The encoder writes a fragment a second, so more pictures than that buy
    /// nothing but heat — and a picture of a real page takes tens of
    /// milliseconds.
    private static let frameInterval: UInt64 = 100_000_000

    public init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // The same rules the phone's browser has — the car is not a loophole.
        AdBlockerEngine.shared.apply(to: configuration)

        webView = WKWebView(frame: CGRect(origin: .zero, size: Self.viewport),
                            configuration: configuration)
        webView.navigationDelegate = delegate
        delegate.onFinish = { [weak self] url in
            guard let self, let url else { return }
            self.address = url.absoluteString
            self.canGoBack = self.webView.canGoBack
            self.canGoForward = self.webView.canGoForward
        }
        delegate.onFail = { reason in
            NSLog("DRIVEPLAY car browser: the page failed: %@", reason)
        }
    }

    // MARK: - Opening a page

    /// Where a page the **car** asks for goes.
    ///
    /// The tests replace it: the real one starts a stream and takes the
    /// player, and a test has no business doing either.
    public static var routeForTheCar: (String) -> Bool = { address in
        openForTheCar(address: address)
    }

    /// Opens a page **for the car**.
    ///
    /// The car's own browser comes first — the app's web view, drawn on the
    /// car's display. The app's own car screen (a second scene) comes next,
    /// and the phone's browser with the screen share is the last resort: it
    /// is the only one of the three that needs the user to start a share.
    @discardableResult
    public static func openForTheCar(address: String,
                                     browser: CarBrowserStream = .shared) -> Bool {
        // The app's own car screen — the one with a real browser UI. It is
        // refused on a phone ("the current device does not support multiple
        // scenes"), so the car's own browser is what actually runs.
        if CarDisplaySession.shared.open(address: address) { return true }
        if browser.open(address: address) { return true }
        BrowserTabManager.shared.loadURLInActiveTab(address)
        ScreenShareService.shared.carRequestedPage(address)
        return false
    }

    /// Opens a page on the car's display.
    @discardableResult
    public func open(address: String) -> Bool {
        guard let destination = BrowserTabItem.destination(for: address),
              let url = URL(string: destination) else { return false }
        load(url: url)
        // The picture is the only way the page reaches the car — so a browser
        // that could not start is not a browser on the car, and the caller
        // falls back to the phone.
        return isRunning
    }

    /// Loads a page — the address is already one.
    func load(url: URL) {
        address = url.absoluteString
        webView.load(URLRequest(url: url))
        start()
    }

    // MARK: - The car's controls

    /// Goes back one page.
    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    /// Goes forward one page.
    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    /// Loads the page again.
    func reload() {
        webView.reload()
    }

    /// Scrolls the page down.
    func scrollDown() {
        scroll(by: 600)
    }

    /// Scrolls the page up.
    func scrollUp() {
        scroll(by: -600)
    }

    /// Scrolls the page — the car's scroll view is not there to be dragged, so
    /// the page is told to scroll itself.
    private func scroll(by points: Int) {
        webView.evaluateJavaScript("window.scrollBy(0, \(points));")
    }

    /// How far the page is scrolled down — the page's own answer, so a test
    /// can tell a page that moved from a picture that did not.
    func scrollOffset() async -> Double {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.scrollY") { value, _ in
                continuation.resume(returning: (value as? NSNumber)?.doubleValue ?? 0)
            }
        }
    }

    /// Closes the page on the car's display.
    func close() {
        stop()
    }

    // MARK: - The picture

    /// Starts the picture.
    private func start() {
        guard writer == nil else { return }

        // Only one picture can be on the car at a time: the phone's screen
        // share stops here, or it would take the player back when it ends.
        ScreenShareService.shared.stop()

        guard let writer = LiveScreenWriter.make() else {
            NSLog("DRIVEPLAY car browser: the encoder could not start")
            return
        }
        let server = ScreenStreamServer(writer: writer)
        self.writer = writer
        self.server = server

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
            NSLog("DRIVEPLAY car browser: the stream server could not start: %@",
                  error.localizedDescription)
            self.writer = nil
            self.server = nil
            return
        }
        isRunning = true
        capture()
    }

    /// Hands the picture to the player — the car draws what the app plays.
    private func publish() {
        guard let port, let server, writer?.playlist() != nil else { return }
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(server.token)/live.m3u8") else { return }
        playlistURL = url
        carBrowserLog.info("the picture is served on port \(port) and handed to the player")
        PlaybackManager.shared.playScreenShare(url: url, title: "Car browser")
    }

    /// Ends the picture.
    func stop() {
        captureTask?.cancel()
        captureTask = nil
        writer?.finish()
        writer = nil
        server?.stop()
        server = nil
        port = nil
        isRunning = false
        playlistURL = nil
        address = ""
        canGoBack = false
        canGoForward = false
        PlaybackManager.shared.stopScreenShare()
    }

    /// Takes the picture of the page and hands it to the encoder — again and
    /// again, so the car sees the page as it is now.
    private func capture() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.capturePicture()
                try? await Task.sleep(nanoseconds: Self.frameInterval)
            }
        }
    }

    /// One picture of the page.
    private func capturePicture() async {
        let image = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { picture, error in
                if let error {
                    carBrowserLog.error("the snapshot failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: picture)
            }
        }
        guard let image, let picture = CIImage(image: image),
              let buffer = ScreenFrameScaler.fit(picture, context: context) else {
            carBrowserLog.error("the page was not drawn — there is no picture to send")
            return
        }
        framesSent += 1
        lastFrame = buffer
        if framesSent % 30 == 1 {
            // A black picture and a page look the same on the car's display —
            // both are "nothing". The brightness is the only thing that tells
            // them apart from inside the app.
            carBrowserLog.info("frame \(self.framesSent) of \(CredentialRedactor.safeForLog(self.address)) — brightness \(Self.brightness(of: buffer))")
        }
        writer?.append(pixelBuffer: buffer,
                       presentationTime: CMTime(value: framesSent, timescale: 30))
    }

    /// The mean brightness of a picture, 0…1.
    ///
    /// A sample of the pixels, not the whole picture: the point is to tell a
    /// black frame from a drawn page, and a page is never uniformly black.
    private static func brightness(of buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return -1 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let stepY = max(1, height / 16)
        let stepX = max(1, width / 16)
        var total: Float = 0
        var samples: Float = 0
        for y in stride(from: 0, to: height, by: stepY) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: stepX) {
                let pixel = row.advanced(by: x * 4)
                total += (Float(pixel[0]) + Float(pixel[1]) + Float(pixel[2])) / (3 * 255)
                samples += 1
            }
        }
        return samples > 0 ? total / samples : -1
    }

    // MARK: - The delegate

    /// Tells the stream what the page did.
    ///
    /// `navigationDelegate` is a **weak** reference, so the stream holds it.
    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (URL?) -> Void = { _ in }
        var onFail: (String) -> Void = { _ in }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            carBrowserLog.info("the page is loaded: \(webView.url.map { CredentialRedactor.safeForLog($0) } ?? "?")")
            onFinish(webView.url)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            onFail(error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            onFail(error.localizedDescription)
        }
    }
}
