import UIKit
import WebKit

/// The probe for the **experimental** CarPlay window role.
///
/// CarPlay's documented API has **no** web template: the system's own headers
/// (`CarPlay.framework/Headers`) carry `CPActionSheetTemplate`,
/// `CPAlertTemplate`, `CPContactTemplate`, `CPGridTemplate`,
/// `CPInformationTemplate`, `CPListTemplate`, `CPMapTemplate`,
/// `CPNowPlayingTemplate`, `CPPointOfInterestTemplate`, `CPSearchTemplate`
/// and `CPTabBarTemplate` — and nothing that can hold a web page. So the
/// only candidate for a *real* WebKit surface on a car's display is a
/// `UIWindow` scene with the experimental role
/// `"UIWindowSceneSessionRoleCarPlay"`.
///
/// This delegate is the **experiment**, not a feature: it says whether iOS
/// ever delivers such a scene on this build. It logs the connection, and when
/// the scene does arrive it puts a real `WKWebView` on it — loading
/// `example.com` — with a Close control.
///
/// The answer is read from the device's log:
///   * `DRIVEPLAY-WEB scene connected role=UIWindowSceneSessionRoleCarPlay`
///     → the experimental window exists, and the browser can be built on it.
///   * only `DRIVEPLAY CarPlay scene connected`
///     → iOS delivers the **template** scene and nothing else: there is no
///     interactive car-side WebKit surface here, and the app must not pretend
///     otherwise.
public final class CarPlayWindowProbe: UIResponder, UIWindowSceneDelegate {

    /// The role the experiment asks for. It is not a documented constant, so
    /// it is built from its raw value — the same way the system names it.
    public static let experimentalRole = UISceneSession.Role(rawValue: "UIWindowSceneSessionRoleCarPlay")

    public var window: UIWindow?

    /// Asks the system for the experimental vehicle window.
    ///
    /// The role is **not** in the SDK: it exists as the private symbol
    /// `__UIWindowSceneSessionRoleCarPlay` in UIKitCore's export list, and the
    /// shipping app CarDash declares it in its manifest
    /// (`"UIWindowSceneSessionRoleCarPlay"` → `UIWindowScene` →
    /// `"HiCar.CastVehicleWindowScene"`). Asking for it is the only way to
    /// learn whether iOS honours it for this app — the answer is in the log:
    /// the scene arrives (`DRIVEPLAY-WEB scene connected`) or the request is
    /// refused (`the vehicle window was refused`).
    public static func requestVehicleWindow() {
        let role = experimentalRole
        NSLog("DRIVEPLAY-WEB asking for the vehicle window (role=%@)", role.rawValue)
        UIApplication.shared.activateSceneSession(
            for: UISceneSessionActivationRequest(role: role)
        ) { error in
            NSLog("DRIVEPLAY-WEB the vehicle window was refused: %@", error.localizedDescription)
        }
    }

    public func scene(_ scene: UIScene,
                      willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
        NSLog("DRIVEPLAY-WEB scene connected role=%@", session.role.rawValue)
        guard session.role.rawValue == Self.experimentalRole.rawValue else {
            NSLog("DRIVEPLAY-WEB not the experimental CarPlay window — role=%@", session.role.rawValue)
            return
        }
        guard let windowScene = scene as? UIWindowScene else {
            NSLog("DRIVEPLAY-WEB the scene is not a UIWindowScene")
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let bounds = windowScene.screen.bounds
        let webView = WKWebView(frame: bounds)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.load(URLRequest(url: URL(string: "https://example.com")!))

        let controller = UIViewController()
        controller.view.backgroundColor = .black
        controller.view.addSubview(webView)

        // A visible Close control: the experiment has to be operable, not just
        // a picture on a screen nobody can touch.
        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        close.layer.cornerRadius = 8
        close.frame = CGRect(x: bounds.width - 120, y: 24, width: 96, height: 44)
        close.addAction(UIAction { _ in
            NSLog("DRIVEPLAY-WEB close tapped")
        }, for: .touchUpInside)
        controller.view.addSubview(close)

        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        NSLog("DRIVEPLAY-WEB window ready bounds=%@", NSCoder.string(for: bounds))
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        NSLog("DRIVEPLAY-WEB scene disconnected")
        window = nil
    }
}
