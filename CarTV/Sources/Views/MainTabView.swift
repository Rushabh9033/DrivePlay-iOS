import SwiftUI

public enum MainTab: Int, Hashable, CaseIterable {
    case home = 0
    case browser = 1
    case vault = 2
    case cockpit = 3
    case settings = 4
}

public struct MainTabView: View {
    @State private var selectedTab: MainTab = .home
    @ObservedObject var playbackManager = PlaybackManager.shared
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // Official Apple Native TabView
            TabView(selection: $selectedTab) {
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
        .onAppear {
            handlePresentationChange(playbackManager.presentationMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
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
}
