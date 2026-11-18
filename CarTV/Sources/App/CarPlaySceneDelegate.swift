import UIKit
import CarPlay

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    public var window: CPWindow?
    public var interfaceController: CPInterfaceController?
    public private(set) var webController: CarPlayWebViewController?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        NSLog("DRIVEPLAY CarPlaySceneDelegate didConnect toWindow: bounds=%@", NSCoder.string(for: window.bounds))
        self.interfaceController = interfaceController
        self.window = window
        attachBrowser(to: window)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        NSLog("DRIVEPLAY CarPlaySceneDelegate didConnect interfaceController")
        self.interfaceController = interfaceController
        let carWindow = templateApplicationScene.carWindow
        self.window = carWindow
        attachBrowser(to: carWindow)
    }

    private func attachBrowser(to window: CPWindow) {
        let controller = CarPlayWebViewController()
        self.webController = controller
        window.rootViewController = controller
        window.makeKeyAndVisible()
        CarDisplaySession.shared.attach(controller)
        NSLog("DRIVEPLAY CarPlaySceneDelegate attached CarPlayWebViewController to CPWindow bounds=%@", NSCoder.string(for: window.bounds))
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        NSLog("DRIVEPLAY CarPlaySceneDelegate didDisconnect fromWindow")
        teardownBrowser()
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        NSLog("DRIVEPLAY CarPlaySceneDelegate didDisconnect")
        teardownBrowser()
    }

    private func teardownBrowser() {
        if let controller = self.webController {
            CarDisplaySession.shared.detach(controller)
            controller.shutDown()
        }
        self.webController = nil
        self.window = nil
        self.interfaceController = nil
    }
}
