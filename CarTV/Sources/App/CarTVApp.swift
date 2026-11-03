import SwiftUI
import CarPlay

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The relay listens from the start: a screen share is started by the
        // user from the Control Center, so the app has to be ready before the
        // broadcast extension announces its stream.
        ScreenShareService.shared.startRelay()

        // A phone that locks itself in the middle of a test run takes the app
        // down with it: the app is backgrounded, the in-flight stream work
        // stops, XCTest times the test out and reports a failure that never
        // happened. Only the app can hold the idle timer, so the tests do it
        // here — a locked phone is the one thing a test run cannot recover from.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            application.isIdleTimerDisabled = true
            NSLog("DRIVEPLAY the idle timer is off (the tests are running)")
        }
        return true
    }

    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        NSLog("DRIVEPLAY AppDelegate configurationForConnecting role: %@", connectingSceneSession.role.rawValue)
        
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        } else if connectingSceneSession.role == .windowExternalDisplay ||
                  connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        return config
    }
}

@main
struct CarTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var playlistStore = PlaylistStore.shared
    @StateObject private var playbackManager = PlaybackManager.shared
    @StateObject private var storeManager = StoreKitManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(playlistStore)
                .environmentObject(playbackManager)
                .environmentObject(storeManager)
                .tint(CarTVTheme.accent)
                .task { await storeManager.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    // The car is showing the video: the phone being minimised or
                    // locked must not stop it.
                    if phase == .background {
                        PlaybackManager.shared.keepPlayingInTheBackground()
                    }
                }
        }
    }
}
