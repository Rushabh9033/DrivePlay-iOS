import SwiftUI

/// The minimised player: the bar at the bottom of the screen that keeps the
/// video's title and its controls in reach while the user browses the app.
///
/// It is **docked**, not floating: it sits above the tab bar, it never moves
/// and it never covers the content. The video keeps playing behind it — the
/// phone draws no picture of its own in this mode, so the frames go into the
/// app's offscreen output and the car's display can still take them.
public struct MiniPlayerBar: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var playlistStore = PlaylistStore.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // The thumbnail and the title are one tap target: the bar opens
            // the player again.
            HStack(spacing: 10) {
                thumbnail
                Text(playbackManager.currentChannel?.name ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CarTVTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { playbackManager.expandFromMiniBar() }

            Button(action: { playbackManager.togglePlayPause() }) {
                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CarTVTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(playbackManager.isPlaying ? "Pause" : "Play")

            Button(action: { playbackManager.playNextChannel(in: siblings) }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CarTVTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Next channel")

            Button(action: { playbackManager.closePlayer() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(CarTVTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("miniPlayerBar")
    }

    /// The channels of the current channel's own group — the list "next"
    /// walks.
    private var siblings: [Channel] {
        guard let channel = playbackManager.currentChannel else { return [] }
        return playlistStore.channels(inGroupOf: channel)
    }

    /// The channel's own picture.
    ///
    /// It is the logo the playlist already carries — the app keeps no frame of
    /// the video, so there is nothing better to show.
    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
            if let logoURL = playbackManager.currentChannel?.logoURL {
                AsyncImage(url: logoURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(3)
                    }
                }
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 14))
                    .foregroundColor(CarTVTheme.textTertiary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The gesture that puts the player away — YouTube's swipe down.
///
/// One rule for both the docked player (a SwiftUI drag) and the landscape
/// fullscreen (a UIKit swipe): a drag that goes **down** minimises, a drag
/// that goes sideways does not.
public enum MiniPlayerSwipe {
    /// How far the finger has to travel downwards before the player goes.
    public static let threshold: CGFloat = 60

    /// A drag that goes down (and not sideways) puts the player away.
    public static func shouldMinimize(translation: CGSize) -> Bool {
        translation.height > threshold && translation.height > abs(translation.width)
    }
}
