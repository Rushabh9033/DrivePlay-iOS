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
        sceneDelegate.handleCarPlayWebSelection("https://m.youtube.com")
        XCTAssertEqual(handsetTabs.tab, .home, "CarPlay web selection must not alter handset active tab")

        sceneDelegate.handleCarPlayWebSelection("google")
        XCTAssertEqual(handsetTabs.tab, .home, "CarPlay discovery selection must not alter handset active tab")

        sceneDelegate.handleCarPlayWebSelection("twitch")
        XCTAssertEqual(handsetTabs.tab, .home, "CarPlay Twitch hub must not alter handset active tab")

        handsetTabs.tab = .vault
        sceneDelegate.handleCarPlayWebSelection("https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")
        XCTAssertEqual(handsetTabs.tab, .vault, "CarPlay video stream playback must not alter handset active tab")
    }

    @MainActor
    func test_carplay_address_bar_independent_from_handset_active_url() {
        let tabManager = BrowserTabManager.shared
        tabManager.activeTabURL = "https://sensitive-handset-portal.internal"

        let search = CarPlayBrowserSearch()
        let expectation = expectation(description: "Search results updated")
        
        search.searchTemplate(CPSearchTemplate(), updatedSearchText: "portal") { results in
            // None of the results should contain the handset's private active tab URL
            let hasHandsetLeak = results.contains { item in
                (item.detailText ?? "").contains("sensitive-handset-portal.internal") ||
                (item.text ?? "").contains("On the phone now")
            }
            XCTAssertFalse(hasHandsetLeak, "CarPlay address bar search must be decoupled from handset active tab URL")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
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
        XCTAssertEqual(tabs.map(\.rawValue), ["Home", "Favorites", "Cast", "Web Video"])
        XCTAssertEqual(CarPlayTab.browser.rawValue, "Web Video")
        XCTAssertEqual(CarPlayTab.browser.symbol, "play.rectangle.on.rectangle.fill")
    }
}
