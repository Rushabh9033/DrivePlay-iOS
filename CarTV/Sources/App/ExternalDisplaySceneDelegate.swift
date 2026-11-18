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
        // Automotive displays must always provide direct interactive controls and real WebKit
        let controller = InCarAutomotiveController(isInteractive: true)
        externalWindow.rootViewController = controller
        externalWindow.isHidden = false
        externalWindow.makeKeyAndVisible()
        self.window = externalWindow
        self.controller = controller
        CarDisplaySession.shared.attach(controller)
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        teardown()
    }

    /// Releases the external display and stops anything it started.
    ///
    /// A screen capture that outlives the scene keeps the system recording
    /// indicator on and drains the battery.
    func teardown() {
        if let controller {
            CarDisplaySession.shared.detach(controller)
            controller.stopMirroring()
        }
        controller = nil
        window = nil
    }
}
