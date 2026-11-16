import SwiftUI
import CarPlay

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NSLog("DRIVEPLAY [1] didFinishLaunchingWithOptions: START")
        print("DRIVEPLAY [1] didFinishLaunchingWithOptions: START")
        fflush(stdout)

        NSLog("DRIVEPLAY [2] starting ScreenShareService relay...")
        print("DRIVEPLAY [2] starting ScreenShareService relay...")
        fflush(stdout)

        // The relay listens from the start: a screen share is started by the
        // user from the Control Center, so the app has to be ready before the
        // broadcast extension announces its stream.
        ScreenShareService.shared.startRelay()

        NSLog("DRIVEPLAY [3] ScreenShareService relay started successfully")
        print("DRIVEPLAY [3] ScreenShareService relay started successfully")
        fflush(stdout)

        // A phone that locks itself in the middle of a test run takes the app
        // down with it: the app is backgrounded, the in-flight stream work
        // stops, XCTest times the test out and reports a failure that never
        // happened. Only the app can hold the idle timer, so the tests do it
        // here — a locked phone is the one thing a test run cannot recover from.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            application.isIdleTimerDisabled = true
            NSLog("DRIVEPLAY the idle timer is off (the tests are running)")
        }

        NSLog("DRIVEPLAY [4] didFinishLaunchingWithOptions: DONE")
        print("DRIVEPLAY [4] didFinishLaunchingWithOptions: DONE")
        fflush(stdout)
        return true
    }

    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let msg = "DRIVEPLAY [SceneConfig] configurationForConnecting role: \(connectingSceneSession.role.rawValue)"
        NSLog("%@", msg)
        print(msg)
        fflush(stdout)
        
        if connectingSceneSession.role == .carTemplateApplication {
            let logMsg = "DRIVEPLAY AppDelegate returning CarPlay Configuration for role: \(connectingSceneSession.role.rawValue)"
            NSLog("%@", logMsg)
            print(logMsg)
            fflush(stdout)
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        } else if connectingSceneSession.role == .windowExternalDisplay ||
                  connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let logMsg = "DRIVEPLAY AppDelegate returning External Display Configuration for role: \(connectingSceneSession.role.rawValue)"
            NSLog("%@", logMsg)
            print(logMsg)
            fflush(stdout)
            let config = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        
        if connectingSceneSession.role == .windowApplication {
            let logMsg = "DRIVEPLAY AppDelegate returning UISceneConfiguration(name: nil) for .windowApplication"
            NSLog("%@", logMsg)
            print(logMsg)
            fflush(stdout)
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }
        
        let logMsg = "DRIVEPLAY AppDelegate fallback returning UISceneConfiguration(name: nil) for role: \(connectingSceneSession.role.rawValue)"
        NSLog("%@", logMsg)
        print(logMsg)
        fflush(stdout)
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
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
                .onAppear {
                    NSLog("DRIVEPLAY [WindowGroup] root onAppear invoked")
                    print("DRIVEPLAY [WindowGroup] root onAppear invoked")
                    fflush(stdout)
                }
                .onChange(of: scenePhase) { _, phase in
                    NSLog("DRIVEPLAY [WindowGroup] scenePhase changed to: %@", String(describing: phase))
                    print("DRIVEPLAY [WindowGroup] scenePhase changed to: \(phase)")
                    fflush(stdout)
                    // The car is showing the video: the phone being minimised or
                    // locked must not stop it.
                    if phase == .background {
                        PlaybackManager.shared.keepPlayingInTheBackground()
                    }
                }
        }
    }
}
