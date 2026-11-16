import XCTest
import UIKit
import WebKit
import CarPlay
@testable import CarTV

final class BrowserOwnershipAndRoleTests: XCTestCase {

    @MainActor
    func test_carplay_actions_preserve_handset_tab_selection() {
        let handsetTabs = AppTabSelection.shared
        handsetTabs.tab = .home

        // Verify CarPlay actions do not modify handset tab selection
        let sceneDelegate = CarPlaySceneDelegate()
        sceneDelegate.togglePlayback()
        XCTAssertEqual(handsetTabs.tab, .home, "CarPlay playback toggle must not alter handset active tab")

        sceneDelegate.togglePicture()
        XCTAssertEqual(handsetTabs.tab, .home, "CarPlay picture toggle must not alter handset active tab")

        handsetTabs.tab = .vault
        let missing = URL(fileURLWithPath: "/tmp/driveplay-no-such-stream.m3u8")
        let channel = Channel(name: "Test", streamURL: missing, groupTitle: "News")
        sceneDelegate.play(channel: channel)
        XCTAssertEqual(handsetTabs.tab, .vault, "CarPlay video stream playback must not alter handset active tab")
    }

    @MainActor
    func test_handset_browser_independent_tabs_and_state() {
        let tabManager = BrowserTabManager.shared
        let originalCount = tabManager.tabs.count
        let originalActive = tabManager.activeTabURL

        tabManager.createNewTab(urlString: "https://duckduckgo.com")
        XCTAssertEqual(tabManager.tabs.count, originalCount + 1)
        XCTAssertEqual(tabManager.activeTabURL, "https://duckduckgo.com")

        // Clean up
        tabManager.closeTab(at: tabManager.tabs.count - 1)
        tabManager.activeTabURL = originalActive
    }

    @MainActor
    func test_in_car_automotive_controller_interactive_mode() {
        let interactiveController = InCarAutomotiveController(isInteractive: true)
        XCTAssertTrue(interactiveController.isInteractive)
        _ = interactiveController.view
        interactiveController.view.layoutIfNeeded()

        // In interactive mode, URL container and interactive views are enabled
        XCTAssertTrue(interactiveController.browserContainer.isUserInteractionEnabled)
    }

    @MainActor
    func test_in_car_automotive_controller_non_interactive_mode() {
        let nonInteractiveController = InCarAutomotiveController(isInteractive: false)
        XCTAssertFalse(nonInteractiveController.isInteractive)
        _ = nonInteractiveController.view
        nonInteractiveController.view.layoutIfNeeded()

        // In non-interactive mode, keyboard toggle is hidden and text field interaction disabled
        XCTAssertFalse(nonInteractiveController.browserUrlTextField.isUserInteractionEnabled)
        XCTAssertTrue(nonInteractiveController.floatingKeyboard.isHidden)
    }

    @MainActor
    func test_screen_relay_car_requested_page_does_not_start_relay() {
        let share = ScreenShareService(relay: ScreenRelayListener(port: 47515))
        defer { share.stopRelay() }

        share.carRequestedPage("https://duckduckgo.com")
        XCTAssertEqual(share.pendingCarPage, "https://duckduckgo.com")
        XCTAssertFalse(share.isWaitingForBroadcast, "Car page request must not start screen relay listener")
    }

    func test_carplay_tabs_honest_naming_and_icons() {
        let tabs = CarPlayTab.allCases
        XCTAssertEqual(tabs.map(\.rawValue), ["Home", "Favorites", "Cast"])
        XCTAssertEqual(CarPlayTab.home.symbol, "house.fill")
        XCTAssertEqual(CarPlayTab.favorites.symbol, "heart.fill")
        XCTAssertEqual(CarPlayTab.cast.symbol, "airplayvideo")
    }
}
