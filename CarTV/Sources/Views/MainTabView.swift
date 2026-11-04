import SwiftUI
import UIKit

public struct MainTabView: View {
    /// The tab the app shows — shared, so the car can bring the browser to
    /// the front (see `AppTabSelection`).
    @ObservedObject private var tabs = AppTabSelection.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var orientationMonitor = DeviceOrientationMonitor.shared
    /// The height of the tab bar, measured from the live window.
    @State private var tabBarHeight: CGFloat = 0

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Official Apple Native TabView
            TabView(selection: $tabs.tab) {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(MainTab.home)

                NavigationStack {
                    InAppBrowserView()
                }
                .tabItem {
                    Label("Browser", systemImage: "safari")
                }
                .tag(MainTab.browser)

                NavigationStack {
                    UniversalOfflineVaultView()
                }
                .tabItem {
                    Label("Vault", systemImage: "folder")
                }
                .tag(MainTab.vault)

                NavigationStack {
                    SatelliteHUDView()
                }
                .tabItem {
                    Label("Cockpit", systemImage: "speedometer")
                }
                .tag(MainTab.cockpit)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
            }
            // The minimised player: a bar that sits **above** the tab bar and
            // keeps the video's title and its controls in reach while the user
            // browses the app.
            //
            // It is an overlay, not a `safeAreaInset`: the tab view on iOS 26+
            // is UIKit's own, and it swallows the inset's content whole — the
            // bar never reaches the screen at all.
            if playbackManager.showsMiniPlayer {
                MiniPlayerBar()
                    .padding(.bottom, tabBarHeight)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }

            // "Browse While You Watch" Docked Player Mode
            if playbackManager.presentationMode == .docked {
                DockedPlayerContainerView()
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playbackManager.presentationMode)
        .onChange(of: playbackManager.presentationMode) { newMode in
            handlePresentationChange(newMode)
        }
        .onChange(of: playbackManager.showsMiniPlayer) { shows in
            // Measure again when the bar appears: the tab bar is certainly in
            // the window by then.
            if shows { tabBarHeight = Self.tabBarHeightInWindow() }
        }
        .onAppear {
            // The orientation notification is only posted while the device is
            // generating them. Without this the handler below never runs and
            // the docked player never rotates into full screen.
            orientationMonitor.start()
            handlePresentationChange(playbackManager.presentationMode)
            tabBarHeight = Self.tabBarHeightInWindow()
        }
        .onDisappear {
            orientationMonitor.stop()
        }
        .onChange(of: orientationMonitor.orientation) { orientation in
            if orientation.isLandscape && playbackManager.presentationMode == .docked {
                playbackManager.enterLandscapeFullscreen()
            } else if orientation == .portrait && playbackManager.presentationMode == .fullscreen {
                playbackManager.exitLandscapeFullscreen()
            }
        }
    }

    private func handlePresentationChange(_ mode: PlayerPresentationMode) {
        if mode == .fullscreen, let player = playbackManager.player {
            NativeFullScreenPlayerPresenter.shared.present(player: player) {
                playbackManager.exitLandscapeFullscreen()
            }
        } else if mode != .fullscreen {
            NativeFullScreenPlayerPresenter.shared.dismiss()
        }
    }

    /// The height of the tab bar in the live window.
    ///
    /// The bar floats over the content on iOS 26+ and its height is not a
    /// constant — a phone with a home indicator and one with a home button
    /// differ — so it is measured rather than guessed.
    static func tabBarHeightInWindow() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let phone = scenes.filter { $0.session.role == .windowApplication }.flatMap(\.windows)
        let window = phone.first { $0.isKeyWindow } ?? phone.first
            ?? scenes.flatMap(\.windows).first
        guard let window else { return 0 }
        return firstTabBar(in: window)?.bounds.height ?? 0
    }

    private static func firstTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let bar = firstTabBar(in: sub) { return bar }
        }
        return nil
    }
}
