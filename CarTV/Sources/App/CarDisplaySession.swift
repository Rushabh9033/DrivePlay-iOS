import Foundation
import OSLog
import UIKit

/// The app's own log — the one that reaches the device's own log.
///
/// `NSLog` only reaches the console a debugger is attached to; the unified
/// log is what a car-launched run leaves behind, and that is the only way to
/// see what the car did to the app.
let carDisplayLog = Logger(subsystem: "com.rushabh.cartvv", category: "CarDisplay")

/// A browser that runs **on the car's display**.
///
/// The app's own car screen is the one that has a real `WKWebView` — CarPlay's
/// templates cannot hold a web page, so a template browser can only ever be a
/// remote control for the phone.
protocol CarBrowserScreen: AnyObject {
    /// Opens the page in the car's own browser.
    func open(address: URL)
}

/// The app's **own** screen on the car's display.
///
/// CarPlay draws the **template** scene itself, and a template cannot be a web
/// page — there is no web template in `CarPlay.framework` at all. So the
/// Browser tab of the template scene can never be a browser: it is a text
/// field and a list of links, and picking one hands the address to the
/// **phone**. That is the *"it works as a remote control for the iPhone"*.
///
/// The app's own car screen — the one with a real `WKWebView`, a toolbar, a
/// zoom control and a full-screen video surface — lives in the **external
/// display** scene. The system opens that scene only when the app asks for
/// it, and on a phone it is allowed only while a CarPlay session is up.
///
/// So this is the one place that knows whether the car has a screen of its
/// own, asks for it, and carries an address to it.
@MainActor
final class CarDisplaySession {

    static let shared = CarDisplaySession()

    /// The car's own screen, while its scene is connected.
    private(set) weak var carScreen: CarBrowserScreen?

    /// True while the car has a screen of its own to draw on.
    var isConnected: Bool { carScreen != nil }

    /// Asks the system for the car's own screen.
    ///
    /// The tests replace it, so they can see the request without a car.
    var activateCarScreen: (UISceneSession.Role) -> Void = { role in
        UIApplication.shared.activateSceneSession(
            for: UISceneSessionActivationRequest(role: role)
        ) { error in
            carDisplayLog.error("the car's own screen was refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    init() {}

    // MARK: - The scene

    /// The car screen arrived.
    func attach(_ screen: CarBrowserScreen) {
        carScreen = screen
        carDisplayLog.notice("the car's own screen is up — the browser runs on the car")
    }

    /// The car screen went away.
    func detach(_ screen: CarBrowserScreen) {
        guard carScreen === screen else { return }
        carScreen = nil
        carDisplayLog.notice("the car's own screen went away")
    }

    /// Asks the system for the car's own screen.
    ///
    /// The scene is the **external display** role: a CarPlay template cannot
    /// be a web page, so the browser that runs *on the car* has to be a scene
    /// of its own. The system opens it on request, and refuses while the
    /// executing environment allows no second scene at all — which on a phone
    /// means the CarPlay session is not up yet.
    func requestCarScreen() {
        guard !isConnected else { return }
        activateCarScreen(.windowExternalDisplayNonInteractive)
    }

    // MARK: - The browser

    /// Opens the address in the car's **own** browser.
    ///
    /// The rules are the phone browser's own: a text that is a URL is a URL,
    /// anything else is a search.
    ///
    /// - Returns: `true` when the car took the page — `false` when there is
    ///   no car screen, and the caller has to fall back to the phone.
    @discardableResult
    func open(address: String) -> Bool {
        guard let carScreen,
              let destination = BrowserTabItem.destination(for: address),
              let url = URL(string: destination) else { return false }
        carScreen.open(address: url)
        return true
    }
}
