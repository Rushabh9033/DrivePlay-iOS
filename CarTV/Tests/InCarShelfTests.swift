import XCTest
@testable import CarTV

/// The car shelves are rebuilt from the channel list, and building them is
/// expensive — so a rebuild has to be skipped when the list did not change.
final class InCarShelfTests: XCTestCase {

    private func channel(_ name: String, favorite: Bool = false) -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                isFavorite: favorite)
    }

    /// AC12: the store republishes the same channels on every save and the
    /// publisher fires once on subscription, so identical data must not look
    /// like a change.
    func test_AC12_shelf_signature_is_unchanged_for_identical_channels() {
        let a = channel("ESPN")
        let b = channel("CNN")
        XCTAssertEqual(InCarAutomotiveController.ShelfSignature(channels: [a, b], favorites: []),
                       InCarAutomotiveController.ShelfSignature(channels: [a, b], favorites: []))
    }

    /// AC13: favouriting a channel does not change the channel list, but it does
    /// change what the shelves show — so it still has to trigger a rebuild.
    func test_AC13_shelf_signature_changes_when_a_channel_becomes_a_favourite() {
        let plain = channel("ESPN")
        let favourite = channel("ESPN", favorite: true)
        XCTAssertNotEqual(InCarAutomotiveController.ShelfSignature(channels: [plain], favorites: []),
                          InCarAutomotiveController.ShelfSignature(channels: [favourite], favorites: [favourite]))
    }

    func test_browserTabSwitchesAndLoadsURLWithoutCrash() {
        let vc = InCarAutomotiveController()
        vc.view.frame = CGRect(x: 0, y: 0, width: 800, height: 480)
        vc.viewDidLoad()
        vc.viewDidLayoutSubviews()
        vc.switchTab(.browser)
        XCTAssertFalse(vc.browserContainer.isHidden)
        vc.openBrowser(url: URL(string: "https://m.youtube.com")!)
        XCTAssertNotNil(vc.webView)
        XCTAssertFalse(vc.webView!.isHidden)
    }
}
