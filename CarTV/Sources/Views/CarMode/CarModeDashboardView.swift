import SwiftUI

public struct CarModeDashboardView: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var playlistStore = PlaylistStore.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showChannelDrawer: Bool = false
    @State private var channelSearchQuery: String = ""
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if isLandscape {
                    landscapeLayout(size: geo.size)
                } else {
                    portraitLayout(size: geo.size)
                }
            }
        }
        .sheet(isPresented: $showChannelDrawer) {
            channelPickerSheet
        }
        .onAppear {
            autoStartPlaybackIfNeeded()
        }
    }
    
    // MARK: - Portrait Layout (Optimized for iPhone in Car Mount)
    
    @ViewBuilder
    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Exit")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(20)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "car.fill")
                        .foregroundColor(CarTVTheme.accent)
                    Text("Car Mode")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: { showChannelDrawer = true }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Video Player Container (16:9 Aspect Ratio)
            ZStack {
                if let player = playbackManager.player {
                    VideoPlayerView(player: player)
                        .cornerRadius(14)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 44))
                            .foregroundColor(CarTVTheme.accent)
                        
                        Text(playlistStore.channels.isEmpty ? "No Channels Added" : "Ready to Play")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        Button {
                            if playlistStore.channels.isEmpty {
                                showChannelDrawer = true
                            } else {
                                startFirstChannel()
                            }
                        } label: {
                            Text(playlistStore.channels.isEmpty ? "Add Channels" : "Start Playback")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(CarTVTheme.accent)
                                .cornerRadius(20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .cornerRadius(14)
                }
                
                // Passenger safety badge
                VStack {
                    Spacer()
                    HStack {
                        Text("Passenger use only")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(height: min(240, size.width * 9 / 16))
            .padding(.horizontal, 16)
            
            // Channel Info Header
            VStack(alignment: .leading, spacing: 4) {
                if let channel = playbackManager.currentChannel {
                    Text(channel.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(channel.groupTitle.isEmpty ? "Live Stream" : channel.groupTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CarTVTheme.accent)
                } else {
                    Text("Select a Channel")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("\(playlistStore.channels.count) channels available")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Primary Oversized Transport Controls
            VStack(spacing: 20) {
                // Prev, Play/Pause, Next Row
                HStack(spacing: 24) {
                    Button(action: playPreviousChannel) {
                        VStack(spacing: 4) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 24, weight: .bold))
                            Text("Prev")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                    }
                    
                    Button(action: handlePlayPause) {
                        Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 88, height: 88)
                            .background(CarTVTheme.accent)
                            .clipShape(Circle())
                            .shadow(color: CarTVTheme.accent.opacity(0.3), radius: 12)
                    }
                    
                    Button(action: playNextChannel) {
                        VStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 24, weight: .bold))
                            Text("Next")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                    }
                }
                
                // Secondary Skip Controls
                HStack(spacing: 40) {
                    Button(action: { playbackManager.skipBackward(seconds: 10) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gobackward.10")
                            Text("10s")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(20)
                    }
                    
                    Button(action: { playbackManager.skipForward(seconds: 10) }) {
                        HStack(spacing: 6) {
                            Text("10s")
                            Image(systemName: "goforward.10")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(20)
                    }
                }
                
                // Channel Drawer Shortcut
                Button(action: { showChannelDrawer = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                        Text("Browse All Channels (\(playlistStore.channels.count))")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CarTVTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Landscape Layout (Wide Screen Experience)
    
    @ViewBuilder
    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // Left 65%: Video Player
            ZStack {
                if let player = playbackManager.player {
                    VideoPlayerView(player: player)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 48))
                            .foregroundColor(CarTVTheme.accent)
                        Text("Car Mode")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Button("Start Playback") {
                            startFirstChannel()
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(CarTVTheme.accent)
                        .cornerRadius(16)
                    }
                }
                
                // Safety badge
                VStack {
                    Spacer()
                    HStack {
                        Text("Passenger use only")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Right 35%: Controls Sidebar
            VStack(spacing: 12) {
                // Top Exit & Channel List
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Exit")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Button(action: { showChannelDrawer = true }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(CarTVTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Channel Info
                if let channel = playbackManager.currentChannel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(channel.groupTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CarTVTheme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
                
                Spacer()
                
                // Big Transport Controls
                HStack(spacing: 20) {
                    Button(action: { playbackManager.skipBackward(seconds: 10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 54, height: 54)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    
                    Button(action: handlePlayPause) {
                        Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 72, height: 72)
                            .background(CarTVTheme.accent)
                            .clipShape(Circle())
                    }
                    
                    Button(action: { playbackManager.skipForward(seconds: 10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 54, height: 54)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                
                Spacer()
                
                // Prev / Next Channel
                HStack(spacing: 12) {
                    Button(action: playPreviousChannel) {
                        Text("‹ Prev")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(10)
                    }
                    
                    Button(action: playNextChannel) {
                        Text("Next ›")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(width: min(320, size.width * 0.40))
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
    }
    
    // MARK: - Channel Picker Sheet
    
    private var channelPickerSheet: some View {
        NavigationStack {
            List {
                if playlistStore.channels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tv.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No channels available")
                            .font(.headline)
                        Text("Add an M3U playlist or Xtream source from Settings to watch live streams.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    let filtered = channelSearchQuery.isEmpty ? playlistStore.channels : playlistStore.channels.filter {
                        $0.name.localizedCaseInsensitiveContains(channelSearchQuery) ||
                        $0.groupTitle.localizedCaseInsensitiveContains(channelSearchQuery)
                    }
                    
                    ForEach(filtered) { ch in
                        Button {
                            playbackManager.play(channel: ch, presentation: .carMode)
                            showChannelDrawer = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")
                                    .foregroundColor(playbackManager.currentChannel?.id == ch.id ? CarTVTheme.accent : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ch.name)
                                        .font(.body.weight(playbackManager.currentChannel?.id == ch.id ? .bold : .regular))
                                        .foregroundColor(.primary)
                                    Text(ch.groupTitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if playbackManager.currentChannel?.id == ch.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(CarTVTheme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $channelSearchQuery, prompt: "Search channels")
            .navigationTitle("Select Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showChannelDrawer = false
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handlePlayPause() {
        if playbackManager.player != nil {
            playbackManager.togglePlayPause()
        } else {
            startFirstChannel()
        }
    }
    
    private func autoStartPlaybackIfNeeded() {
        if playbackManager.player == nil && !playlistStore.channels.isEmpty {
            startFirstChannel()
        }
    }
    
    private func startFirstChannel() {
        guard let first = playlistStore.channels.first else { return }
        playbackManager.play(channel: first, presentation: .carMode)
    }
    
    private func playNextChannel() {
        let channels = playlistStore.channels
        guard !channels.isEmpty else { return }
        if let current = playbackManager.currentChannel,
           let idx = channels.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = (idx + 1) % channels.count
            playbackManager.play(channel: channels[nextIdx], presentation: .carMode)
        } else {
            playbackManager.play(channel: channels[0], presentation: .carMode)
        }
    }
    
    private func playPreviousChannel() {
        let channels = playlistStore.channels
        guard !channels.isEmpty else { return }
        if let current = playbackManager.currentChannel,
           let idx = channels.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + channels.count) % channels.count
            playbackManager.play(channel: channels[prevIdx], presentation: .carMode)
        } else {
            playbackManager.play(channel: channels[0], presentation: .carMode)
        }
    }
}
