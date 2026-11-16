import CoreVideo
import XCTest
import UIKit
@testable import CarTV

/// The browser that runs **on the car's display**.
///
/// CarPlay cannot draw a web page — there is no web template in
/// `CarPlay.framework` at all — so what the car draws is the video the app
/// plays. The browser on the car is therefore the app's own web view, drawn
/// into the same chain the TV channels use:
///
///     the web view → a picture → the encoder → a local HTTP server → the app's AVPlayer
///
/// These tests cover the three facts that chain rests on: the page can be
/// **captured** while it is not on the phone's screen, the picture **follows**
/// the page, and the picture reaches the car as a **stream** the app plays.
@MainActor
final class CarBrowserStreamTests: XCTestCase {

    // MARK: - The pages

    /// A page that is unmistakable in a picture: green, with a black square in
    /// the middle. The square is **fixed**, so it stays in the middle however
    /// far the page is scrolled.
    private static let markedPage = """
    <html><head><meta name="viewport" content="width=device-width">
    <style>html,body{margin:0;height:100%;background:rgb(0,200,0)}
    #mark{position:fixed;left:50%;top:50%;width:120px;height:120px;margin:-60px 0 0 -60px;background:#000}
    </style></head><body><div id="mark"></div></body></html>
    """

    /// A page with a black **bar** across the top and a long green tail below
    /// it, so scrolling takes the bar out of the picture.
    ///
    /// The bar is as wide as the page on purpose: the picture's rows may be
    /// the page's bottom or its top (the encoder's canvas and the web view's
    /// layout disagree about which way is up), and a bar that spans the whole
    /// width is found either way.
    private static let scrollingPage = """
    <html><head><meta name="viewport" content="width=device-width">
    <style>html,body{margin:0;height:100%;background:rgb(0,200,0)}
    #mark{position:absolute;left:0;top:0;width:100%;height:120px;background:#000}
    #tail{height:3000px;background:rgb(0,200,0)}
    </style></head><body><div id="mark"></div><div id="tail"></div></body></html>
    """

    // MARK: - AC165

    /// AC165: the car's browser can be captured as a picture.
    ///
    /// The web view is **not on the phone's screen** — it is in no window at
    /// all — and a picture of it has to carry the page, or the car's display
    /// would show a black screen where the page should be.
    func test_AC165_the_cars_browser_can_be_captured() async throws {
        let browser = CarBrowserStream()
        defer { browser.stop() }
        browser.load(url: try writePage(Self.markedPage))

        let picture = await waitForPicture(of: browser) { frame in
            isGreen(pixel(in: frame, x: 4, y: 4))
                && isBlack(pixel(in: frame, x: width(of: frame) / 2, y: height(of: frame) / 2))
        }
        let frame = try XCTUnwrap(picture,
                                  "no picture of the page ever arrived — the car's browser would be black")

        XCTAssertEqual(width(of: frame), Int(CarBrowserStream.viewport.width),
                       "the picture is not the size of the car's screen")
        XCTAssertEqual(height(of: frame), Int(CarBrowserStream.viewport.height),
                       "the picture is not the size of the car's screen")
    }

    // MARK: - AC166

    /// AC166: the picture follows the page.
    ///
    /// The picture is taken again and again, so a page that moves is seen as
    /// it is now — a web view that froze on its first picture would show the
    /// top of the page for ever, and the car's "scroll down" would do nothing.
    func test_AC166_the_picture_follows_the_page() async throws {
        let browser = CarBrowserStream()
        defer { browser.stop() }
        browser.load(url: try writePage(Self.scrollingPage))

        let first = await waitForPicture(of: browser) { hasBarAtTheTop($0) }
        _ = try XCTUnwrap(first, "the page's bar never appeared in a picture")

        // The car's own "scroll down" row.
        let before = browser.framesSent
        browser.scrollDown()

        let scrolled = await waitForPicture(of: browser, after: before) { !hasBarAtTheTop($0) }
        _ = try XCTUnwrap(scrolled,
                          "the picture did not follow the page — it is frozen on the first frame")

        // The page really moved — otherwise the test would be measuring the
        // wrong thing.
        let offset = await browser.scrollOffset()
        XCTAssertGreaterThan(offset, 0, "the page did not scroll at all")
    }

    // MARK: - AC167

    /// AC167: the page reaches the car as a stream.
    ///
    /// The car draws the video the app plays, so the pictures have to become a
    /// playlist the app can play — the very playlist the app serves.
    func test_AC167_the_page_reaches_the_car_as_a_stream() async throws {
        let browser = CarBrowserStream()
        defer { browser.stop() }
        browser.load(url: try writePage(Self.markedPage))

        let address = await waitForPlaylist(of: browser)
        let playlist = try XCTUnwrap(address,
                                     "the browser never served a playlist — the car would have nothing to draw")

        // The playlist is served over HTTP, with the token in its path.
        let (data, response) = try await URLSession.shared.data(from: playlist)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("#EXTM3U"), "that is not a playlist")
        XCTAssertTrue(text.contains("init.mp4"), "the playlist has no initialisation segment")
        XCTAssertTrue(text.contains(".m4s"), "the playlist has no fragments")

        // The app plays the very stream it serves — that is what puts the
        // page on the car's display.
        XCTAssertEqual(PlaybackManager.shared.currentChannel?.streamURL, playlist,
                       "the app is not playing the browser's own stream")
    }

    // MARK: - The helpers

    /// Writes a page to a file and gives its address back.
    private func writePage(_ html: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("car-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("page.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Waits for a picture that answers the question.
    ///
    /// The wait is on the **condition**, not on a fixed delay: the pictures
    /// come as fast as the page can be shot, and a page that is slow to load
    /// must not fail the test. A picture that never answers the question is
    /// **nothing** — the wait ends with no picture, so the test fails instead
    /// of passing on the last frame it happened to see.
    private func waitForPicture(of browser: CarBrowserStream,
                                after frameCount: Int64 = 0,
                                timeout: TimeInterval = 30,
                                isRight: (CVPixelBuffer) -> Bool) async -> CVPixelBuffer? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = browser.lastFrame, browser.framesSent > frameCount, isRight(frame) {
                return frame
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    /// Waits for the playlist the app plays.
    private func waitForPlaylist(of browser: CarBrowserStream,
                                 timeout: TimeInterval = 30) async -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let url = browser.playlistURL { return url }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    /// True while the page's black bar is in the picture — at the top of the
    /// page or at its bottom, whichever way up the picture is.
    private func hasBarAtTheTop(_ frame: CVPixelBuffer) -> Bool {
        let middle = width(of: frame) / 2
        return isBlack(pixel(in: frame, x: middle, y: 60))
            || isBlack(pixel(in: frame, x: middle, y: height(of: frame) - 60))
    }

    private func width(of frame: CVPixelBuffer) -> Int { CVPixelBufferGetWidth(frame) }
    private func height(of frame: CVPixelBuffer) -> Int { CVPixelBufferGetHeight(frame) }

    /// One pixel of a picture — blue, green, red, alpha (the canvas is BGRA).
    private func pixel(in frame: CVPixelBuffer, x: Int, y: Int) -> (b: Int, g: Int, r: Int, a: Int)? {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let w = width(of: frame)
        let h = height(of: frame)
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let offset = y * CVPixelBufferGetBytesPerRow(frame) + x * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
    }

    private func isGreen(_ pixel: (b: Int, g: Int, r: Int, a: Int)?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 120 && pixel.g > 120 && pixel.b < 120
    }

    private func isBlack(_ pixel: (b: Int, g: Int, r: Int, a: Int)?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 60 && pixel.g < 60 && pixel.b < 60
    }
}
