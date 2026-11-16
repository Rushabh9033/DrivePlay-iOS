import UIKit

public final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?
    /// The controller shown on the external display. Its screen capture has to be
    /// stopped when the display goes away.
    var controller: InCarAutomotiveController?

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let externalWindow = UIWindow(windowScene: windowScene)
        let isInteractive: Bool
        if #available(iOS 16.0, *) {
            isInteractive = (session.role != .windowExternalDisplayNonInteractive)
        } else {
            isInteractive = true
        }

        let controller = InCarAutomotiveController(isInteractive: isInteractive)
        externalWindow.rootViewController = controller
        externalWindow.isHidden = false
        externalWindow.makeKeyAndVisible()
        self.window = externalWindow
        self.controller = controller
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        teardown()
    }

    /// Releases the external display and stops anything it started.
    ///
    /// A screen capture that outlives the scene keeps the system recording
    /// indicator on and drains the battery.
    func teardown() {
        controller?.stopMirroring()
        controller = nil
        window = nil
    }
}
