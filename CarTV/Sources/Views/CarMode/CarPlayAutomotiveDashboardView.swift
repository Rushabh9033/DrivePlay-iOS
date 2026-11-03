import SwiftUI
import AVKit
import WebKit
import Combine

public struct CarPlayAutomotiveDashboardView: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var playlistStore = PlaylistStore.shared
    
    // Exactly 4 clean tabs matching reference app recording
    public enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case favorites = "Favorites"
        case cast = "Cast"
        case browser = "Browser"
        
        public var id: String { rawValue }
    }
    
    @State private var selectedTab: Tab = .home
    @State private var isFullScreenVideo: Bool = false
    @State private var showControlsOverlay: Bool = true
    @State private var selectedCategory: String = "All"
    @State private var channelSearchText: String = ""
    @State private var showSearchOverlay: Bool = false
    
    // In-Car Browser State
    @State private var browserURLInput: String = ""
    @State private var currentWebTitle: String = ""
    @State private var webView = WKWebView()
    @State private var isMirroringActive: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Dark Background (#16171B) matching CarTV reference video
            Color(red: 0.09, green: 0.09, blue: 0.11)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top Capsule Tab Bar: [ Home ] [ Favorites ] [ Cast ] [ Browser ] ( 🔍 )
                if selectedTab != .browser || webView.url == nil {
                    automotiveTopBar
                }
                
                // Active Screen Content
                ZStack {
                    switch selectedTab {
                    case .home:
                        homeContentView
                    case .favorites:
                        favoritesContentView
                    case .cast:
                        castContentView
                    case .browser:
                        browserContentView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Search Overlay (When 🔍 is tapped)
            if showSearchOverlay {
                searchOverlayView
                    .transition(.opacity)
            }
            
            // Full-Screen Video Player Overlay (When video is playing)
            if isFullScreenVideo && playbackManager.currentChannel != nil {
                fullScreenVideoOverlay
                    .transition(.opacity)
            }
            
            // Mini Video Bar at Bottom Right (when browsing channels while playing)
            if !isFullScreenVideo && playbackManager.currentChannel != nil && selectedTab != .browser {
                miniPlayerFloatingCard
            }
        }
        .colorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MirroringStarted"))) { _ in
            self.isMirroringActive = true
            self.selectedTab = .cast
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MirroringStopped"))) { _ in
            self.isMirroringActive = false
        }
    }
    
    // MARK: - 1. Top Capsule Tab Bar (Matches Frame 04.5 & 20.5)
    
    private var automotiveTopBar: some View {
        HStack(spacing: 12) {
            Spacer()
            
            // Centered Capsule Tabs
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.70))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == tab ?
                                Color(red: 0.0, green: 0.78, blue: 0.38) : // Vibrant Green (#00C761)
                                Color.clear
                            )
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.08))
            .cornerRadius(24)
            
            Spacer()
            
            // Circular Search Button (🔍) on Far Right
            Button(action: {
                withAnimation {
                    showSearchOverlay.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .frame(height: 56)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }
    
    // MARK: - 2. Home Tab Content ("WHAT WE PLAYING")
    
    private var homeContentView: some View {
        Group {
            let channels = filteredChannels
            if playlistStore.channels.isEmpty {
                // Native Empty State (Frame 04.5: Monitor outline + "Nothing to show")
                VStack(spacing: 14) {
                    Image(systemName: "tv")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(Color(white: 0.35))
                    Text("Nothing to show")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Add sources on your iPhone first")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Category Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["All", "Movies", "Sports", "News", "Series", "Live TV"], id: \.self) { cat in
                                    Button(action: { selectedCategory = cat }) {
                                        Text(cat)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(selectedCategory == cat ? .black : .white.opacity(0.85))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 7)
                                            .background(selectedCategory == cat ? Color(red: 0.0, green: 0.78, blue: 0.38) : Color.white.opacity(0.08))
                                            .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Channel Grid (Tap to play full-screen VIDEO!)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(channels.prefix(80)) { channel in
                                Button(action: {
                                    playVideoDirectly(channel)
                                }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(red: 0.0, green: 0.78, blue: 0.38).opacity(0.18))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 15))
                                                .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(channel.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                Text(channel.resolutionLabel)
                                                    .font(.system(size: 9, weight: .black))
                                                    .foregroundColor(.black)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color(red: 0.0, green: 0.78, blue: 0.38))
                                                    .cornerRadius(3)
                                                
                                                Text(channel.groupTitle.isEmpty ? "Live" : channel.groupTitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(white: 0.6))
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color(red: 0.13, green: 0.14, blue: 0.17))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
        }
    }
    
    // MARK: - 3. Favorites Tab Content ("FAVOURITE")
    
    private var favoritesContentView: some View {
        Group {
            let favorites = playlistStore.favoriteChannels
            if favorites.isEmpty {
                // Native Empty State (Frame 08.5: Heart outline + "Nothing saved yet")
                VStack(spacing: 14) {
                    Image(systemName: "heart")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(Color(white: 0.35))
                    Text("Nothing saved yet")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Touch and hold any channel or poster to keep it here.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(favorites) { channel in
                            Button(action: {
                                playVideoDirectly(channel)
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 0.0, green: 0.78, blue: 0.38).opacity(0.18))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 15))
                                            .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(channel.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(channel.groupTitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(white: 0.6))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(red: 0.13, green: 0.14, blue: 0.17))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    
    // MARK: - 4. Cast Tab Content ("MOBILE MIRRORING" - Matches Frame 20.5)
    
    private var castContentView: some View {
        ZStack {
            if isMirroringActive {
                // Live Screen Mirror Receiver
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("LIVE SCREEN MIRRORING")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.25))
                    .cornerRadius(16)
                    
                    Text("iPhone Display Mirror Active on Car Screen")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Exact Replica of Frame 20.5
                VStack(spacing: 16) {
                    Image(systemName: "tv")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                    
                    Text("Cast anything to this screen")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("On your iPhone, open DrivePlay and go to Discover → Cast to\nScreen to get started.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                        Text("DrivePlay (iPhone)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
    }
    
    // MARK: - 5. In-Car Browser Tab (Matches Frame 12.5 & 13.0)
    
    private var browserContentView: some View {
        VStack(spacing: 0) {
            // Full In-Car Browser Navigation Bar (Frame 12.5)
            HStack(spacing: 10) {
                // Close [✕] Button (returns to Home)
                Button(action: {
                    withAnimation {
                        selectedTab = .home
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                
                // Back Button [<]
                Button(action: {
                    if webView.canGoBack { webView.goBack() }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(webView.canGoBack ? .white : .white.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                // Sidebar / Home Button [🏠]
                Button(action: {
                    browserURLInput = ""
                    webView.load(URLRequest(url: URL(string: "about:blank")!))
                }) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                // Address Bar: [ Enter a URL...  ⟳ ]
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                    
                    TextField("Enter a URL...", text: $browserURLInput, onCommit: {
                        loadWebURL(browserURLInput)
                    })
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    
                    if !browserURLInput.isEmpty {
                        Button(action: {
                            loadWebURL(browserURLInput)
                        }) {
                            Text("GO")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.0, green: 0.78, blue: 0.38))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        webView.reload()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(white: 0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                
                // Tabs [ 1 ]
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    Text("1")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)
                
                // Bookmark Star [★]
                Image(systemName: "star")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                
                // Fullscreen Video / PiP [⛶]
                Image(systemName: "pip.enter")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.11, green: 0.12, blue: 0.14))
            
            // Browser Body: Either Bookmarks Grid (Frame 13.0) or Live WebKit Page
            if browserURLInput.isEmpty {
                // Exact Replica of Frame 13.0 Bookmark Grid
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Games & Tools
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Games & Tools")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 20) {
                                browserAppTile(name: "Game", icon: "gamecontroller.fill", color: Color.purple) {
                                    loadWebURL("https://poki.com")
                                }
                                browserAppTile(name: "Google", icon: "magnifyingglass", color: Color.blue) {
                                    loadWebURL("https://www.google.com")
                                }
                            }
                        }
                        
                        // Section 2: Video & Music
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Video & Music")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 20)], spacing: 18) {
                                browserAppTile(name: "YouTube", icon: "play.rectangle.fill", color: Color.red) {
                                    loadWebURL("https://m.youtube.com")
                                }
                                browserAppTile(name: "Prime Video", icon: "play.tv.fill", color: Color.blue) {
                                    loadWebURL("https://www.primevideo.com")
                                }
                                browserAppTile(name: "Twitch", icon: "livephoto", color: Color.purple) {
                                    loadWebURL("https://m.twitch.tv")
                                }
                                browserAppTile(name: "Pluto TV", icon: "tv.fill", color: Color.yellow) {
                                    loadWebURL("https://pluto.tv")
                                }
                                browserAppTile(name: "Tubi", icon: "film.fill", color: Color.orange) {
                                    loadWebURL("https://tubitv.com")
                                }
                                browserAppTile(name: "Plex", icon: "server.rack", color: Color.yellow) {
                                    loadWebURL("https://app.plex.tv")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                // Live Interactive Web Page directly on the car display!
                CarPlayWebViewRepresentable(webView: webView)
                    .edgesIgnoringSafeArea(.bottom)
            }
        }
    }
    
    private func browserAppTile(name: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color)
                        .frame(width: 58, height: 58)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                }
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func loadWebURL(_ str: String) {
        var formatted = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            if formatted.contains(".") && !formatted.contains(" ") {
                formatted = "https://" + formatted
            } else {
                formatted = "https://www.google.com/search?q=" + (formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? formatted)
            }
        }
        if let url = URL(string: formatted) {
            self.browserURLInput = formatted
            self.webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - 6. Search Overlay View (🔍)
    
    private var searchOverlayView: some View {
        ZStack {
            Color.black.opacity(0.90).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                    TextField("Search channels and videos...", text: $channelSearchText)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    Button("Done") {
                        withAnimation {
                            showSearchOverlay = false
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                }
                .padding(14)
                .background(Color(red: 0.14, green: 0.15, blue: 0.18))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredChannels.prefix(25)) { ch in
                            Button(action: {
                                showSearchOverlay = false
                                playVideoDirectly(ch)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(ch.groupTitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(red: 0.11, green: 0.12, blue: 0.15))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // MARK: - 7. Full-Screen Video Player Overlay
    
    private var fullScreenVideoOverlay: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = playbackManager.player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Passenger Wide-Screen Controls Overlay
            if showControlsOverlay {
                VStack {
                    // Top Player Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.0, green: 0.78, blue: 0.38))
                                    .frame(width: 8, height: 8)
                                Text("LIVE VIDEO")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                            }
                            Text(playbackManager.currentChannel?.name ?? "Video Stream")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // Close / Minimize Video Button [✕]
                        Button(action: {
                            withAnimation {
                                isFullScreenVideo = false
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.85), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Spacer()
                    
                    // Bottom Controls Bar
                    HStack(spacing: 36) {
                        Button(action: { playbackManager.skipBackward(seconds: 10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.0, green: 0.78, blue: 0.38))
                                    .frame(width: 56, height: 56)
                                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.black)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.skipForward(seconds: 10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .onTapGesture {
            withAnimation {
                showControlsOverlay.toggle()
            }
        }
    }
    
    // MARK: - 8. Mini Player Floating Card
    
    private var miniPlayerFloatingCard: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        isFullScreenVideo = true
                    }
                }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.78, blue: 0.38))
                                .frame(width: 32, height: 32)
                            Image(systemName: playbackManager.isPlaying ? "speaker.wave.3.fill" : "play.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.black)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playbackManager.currentChannel?.name ?? "Video Playing")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("Tap to Expand")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.38))
                        }
                        
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(10)
                    .background(Color(red: 0.14, green: 0.15, blue: 0.18))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var filteredChannels: [Channel] {
        var list = playlistStore.channels
        if selectedCategory != "All" {
            list = list.filter {
                $0.groupTitle.localizedCaseInsensitiveContains(selectedCategory)
            }
        }
        if !channelSearchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(channelSearchText) ||
                $0.groupTitle.localizedCaseInsensitiveContains(channelSearchText)
            }
        }
        return list
    }
    
    private func playVideoDirectly(_ channel: Channel) {
        playbackManager.play(channel: channel, presentation: .carMode)
        withAnimation {
            isFullScreenVideo = true
        }
    }
}

// MARK: - WebKit Representable for In-Car Browser

public struct CarPlayWebViewRepresentable: UIViewRepresentable {
    public let webView: WKWebView
    
    public init(webView: WKWebView) {
        self.webView = webView
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        self.webView.scrollView.backgroundColor = .clear
        self.webView.allowsBackForwardNavigationGestures = true
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        return webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
