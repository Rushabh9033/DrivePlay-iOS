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

    // MARK: - Experimental CarPlay Window Scene Browser Tests

    func test_carplay_window_scene_role_registered_in_info_plist() throws {
        guard let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist") ??
              Bundle(for: Self.self).path(forResource: "Info", ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let sceneManifest = plist["UIApplicationSceneManifest"] as? [String: Any],
              let sceneConfigs = sceneManifest["UISceneConfigurations"] as? [String: Any] else {
            let manifest = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any]
            let configs = manifest?["UISceneConfigurations"] as? [String: Any]
            let carPlayWindowScenes = configs?["UIWindowSceneSessionRoleCarPlay"] as? [[String: Any]]
            XCTAssertNotNil(carPlayWindowScenes, "Info.plist must declare UIWindowSceneSessionRoleCarPlay")
            let firstConfig = carPlayWindowScenes?.first
            XCTAssertEqual(firstConfig?["UISceneDelegateClassName"] as? String, "CarTV.CarPlayWindowSceneDelegate")
            return
        }

        let carPlayWindowScenes = sceneConfigs["UIWindowSceneSessionRoleCarPlay"] as? [[String: Any]]
        XCTAssertNotNil(carPlayWindowScenes, "Info.plist must declare UIWindowSceneSessionRoleCarPlay")
        let firstConfig = carPlayWindowScenes?.first
        XCTAssertEqual(firstConfig?["UISceneDelegateClassName"] as? String, "CarTV.CarPlayWindowSceneDelegate")
    }

    @MainActor
    func test_carplay_web_view_controller_lifecycle_and_components() {
        let webVC = CarPlayWebViewController()
        XCTAssertNotNil(webVC.view)
        webVC.view.layoutIfNeeded()

        // Verify webview and subviews
        XCTAssertNotNil(webVC.currentWebView)
        XCTAssertTrue(webVC.currentWebView is WKWebView)
        XCTAssertNotNil(webVC.keyboard)
        XCTAssertTrue(webVC.keyboard is CarPlayFloatingKeyboardView)
        XCTAssertNotNil(webVC.address)
        XCTAssertNotNil(webVC.progress)
        XCTAssertNotNil(webVC.lockOverlay)

        // Clean up
        webVC.shutDown()
    }

    @MainActor
    func test_carplay_floating_keyboard_delegate_interaction() {
        let webVC = CarPlayWebViewController()
        _ = webVC.view
        webVC.view.layoutIfNeeded()

        let keyboard = webVC.keyboard

        // Verify entering text, delete, clear, and dismiss do not crash
        webVC.floatingKeyboard(keyboard, didEnterText: "test")
        webVC.floatingKeyboardDidTapDelete(keyboard)
        webVC.floatingKeyboardDidTapClear(keyboard)
        webVC.floatingKeyboard(keyboard, didSelectQuickItem: "google.com")
        webVC.floatingKeyboardDidTapDismiss(keyboard)

        webVC.shutDown()
    }

    func test_carplay_destination_parsing() {
        // Valid URL
        XCTAssertEqual(CarPlayWebViewController.destination(for: "https://apple.com")?.absoluteString, "https://apple.com")
        // Domain shortcut
        XCTAssertEqual(CarPlayWebViewController.destination(for: "apple.com")?.absoluteString, "https://apple.com")
        // Query search fallback
        XCTAssertTrue(CarPlayWebViewController.destination(for: "weather in cupertino")?.absoluteString.contains("google.com/search") == true)
    }
}
