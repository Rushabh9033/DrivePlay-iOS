import SwiftUI

public struct DockedPlayerContainerView: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var playlistStore = PlaylistStore.shared
    @State private var selectedCategory: String = "All"
    @State private var searchQuery: String = ""
    @State private var displayLimit: Int = 100
    
    // Deferred asynchronous loading: video plays immediately, catalog loads smoothly after appearance
    @State private var isCatalogLoaded: Bool = false
    @State private var playlistChannels: [Channel] = []
    @State private var playlistGroups: [ChannelGroup] = []
    
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    
    public init() {}
    
    private var activeSourceId: UUID? {
        playbackManager.currentChannel?.sourceId
    }
    
    private var activeSource: PlaylistSource? {
        guard let id = activeSourceId else { return nil }
        return playlistStore.sources.first { $0.id == id }
    }
    
    private var filteredChannels: [Channel] {
        var list = playlistChannels
        if selectedCategory != "All" {
            list = list.filter { $0.groupTitle == selectedCategory }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }
        return list
    }
    
    private var displayedChannels: [Channel] {
        if !searchQuery.isEmpty {
            return filteredChannels
        }
        return Array(filteredChannels.prefix(displayLimit))
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Seamless black background extending into safe areas
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Docked Video Player (Clean Docked Controls - Native player reserved for Landscape Fullscreen)
                if let player = playbackManager.player {
                    ZStack {
                        VideoPlayerView(
                            player: player,
                            showsPlaybackControls: false
                        )
                        .background(Color.black)
                        
                        PlayerControlsOverlay(
                            onBack: {
                                playbackManager.closePlayer()
                            },
                            onToggleFullscreen: {
                                withAnimation {
                                    playbackManager.enterLandscapeFullscreen()
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250) // Prominent, larger video display
                    .background(Color.black)
                    .clipped()
                    // Swiping the picture down puts the player away — the
                    // minimised bar takes over from there.
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if MiniPlayerSwipe.shouldMinimize(translation: value.translation) {
                                    playbackManager.minimizeToMiniBar()
                                }
                            }
                    )
                }
                
                // Bottom "Browse While You Watch" Catalog (Playlist-specific)
                VStack(spacing: 8) {
                    // Active Playlist Header & Source Identity
                    if let source = activeSource {
                        HStack(spacing: 8) {
                            Image(systemName: source.type.iconName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(CarTVTheme.accent)
                            
                            Text(source.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(CarTVTheme.textPrimary)
                                .lineLimit(1)
                            
                            Text("• \(filteredChannels.count) items")
                                .font(.system(size: 12))
                                .foregroundColor(CarTVTheme.textSecondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    }
                    
                    // Search bar inside active playlist
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        
                        TextField("Search in this playlist...", text: $searchQuery)
                            .font(.system(size: 13))
                        
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.secondarySystemFill))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    
                    // Category Filter Pills (Only categories from this specific playlist)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryPill(title: "All")
                            ForEach(playlistGroups) { group in
                                categoryPill(title: group.name)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                    
                    // Content Area (Deferred smooth loading)
                    if !isCatalogLoaded {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .tint(CarTVTheme.accent)
                            Text("Loading playlist...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 2-Column Channel Grid (Filtered playlist channels strictly bounded)
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(displayedChannels) { channel in
                                    ChannelCardView(
                                        channel: channel,
                                        onPlay: {
                                            playbackManager.play(channel: channel, presentation: .docked)
                                        },
                                        onFavorite: {
                                            playlistStore.toggleFavorite(for: channel)
                                            // The grid renders a snapshot of the channel
                                            // list, so the heart would never update
                                            // unless the snapshot is kept in step.
                                            if let idx = playlistChannels.firstIndex(where: { $0.id == channel.id }) {
                                                playlistChannels[idx].isFavorite.toggle()
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            
                            if displayedChannels.count < filteredChannels.count {
                                Button {
                                    displayLimit += 100
                                } label: {
                                    Text("Load More Videos (\(displayedChannels.count) of \(filteredChannels.count))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(CarTVTheme.accent)
                                        .padding(.vertical, 12)
                                }
                            }
                            
                            Color.clear.frame(height: 24)
                        }
                    }
                }
                .background(CarTVTheme.background)
            }
        }
        .task(id: activeSourceId) {
            isCatalogLoaded = false
            try? await Task.sleep(nanoseconds: 30_000_000)
            let channels: [Channel]
            let groups: [ChannelGroup]
            if let sourceId = activeSourceId {
                channels = playlistStore.channels(for: sourceId)
                groups = playlistStore.groups(for: sourceId)
            } else {
                channels = playlistStore.channels
                groups = playlistStore.groups
            }
            await MainActor.run {
                self.playlistChannels = channels
                self.playlistGroups = groups
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.isCatalogLoaded = true
                }
            }
        }
    }
    
    private func categoryPill(title: String) -> some View {
        let isSelected = selectedCategory == title
        return Button(action: {
            withAnimation(.spring(response: 0.3)) {
                selectedCategory = title
                displayLimit = 100
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? CarTVTheme.accent : Color(UIColor.tertiarySystemFill))
                .foregroundColor(isSelected ? .white : CarTVTheme.textPrimary)
                .cornerRadius(20)
        }
    }
}
