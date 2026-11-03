import SwiftUI

public struct FavoritesView: View {
    @ObservedObject var playlistStore = PlaylistStore.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]
    
    public var body: some View {
        NavigationStack {
            Group {
                if playlistStore.favoriteChannels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundColor(CarTVTheme.textTertiary)
                        
                        Text("No Favorites Yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(CarTVTheme.textPrimary)
                        
                        Text("Tap the heart on any channel or video to access it quickly here.")
                            .font(.system(size: 14))
                            .foregroundColor(CarTVTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(playlistStore.favoriteChannels) { channel in
                                ChannelCardView(
                                    channel: channel,
                                    onPlay: {
                                        playbackManager.play(channel: channel, presentation: .docked)
                                    },
                                    onFavorite: {
                                        playlistStore.toggleFavorite(for: channel)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Favorites")
        }
    }
}
