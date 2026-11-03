import SwiftUI

public struct ChannelCardView: View {
    public let channel: Channel
    public let onPlay: () -> Void
    public let onFavorite: () -> Void
    
    public init(channel: Channel, onPlay: @escaping () -> Void, onFavorite: @escaping () -> Void) {
        self.channel = channel
        self.onPlay = onPlay
        self.onFavorite = onFavorite
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Strictly bounded 16:9 Video Thumbnail Container
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.secondarySystemFill))
                
                // Channel Logo / Thumbnail strictly fitted inside card bounds
                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(10)
                        case .failure, .empty:
                            placeholderView
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
                
                // Translucent Center Play Button
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
                
                // Top Badges: Resolution (Left) & Favorite (Right)
                VStack {
                    HStack {
                        Text(channel.resolutionLabel.isEmpty ? "HD" : channel.resolutionLabel)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        Button(action: onFavorite) {
                            Image(systemName: channel.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(channel.isFavorite ? .red : .white)
                                .padding(5)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(6)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            
            // Channel Title & Subtitle Badge
            HStack(alignment: .center, spacing: 4) {
                Text(channel.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CarTVTheme.textPrimary)
                    .lineLimit(1)
                
                Spacer(minLength: 2)
                
                Image(systemName: "captions.bubble")
                    .font(.system(size: 11))
                    .foregroundColor(CarTVTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(UIColor.secondarySystemFill), Color(UIColor.tertiarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: iconForGroup(channel.groupTitle))
                .font(.system(size: 24))
                .foregroundColor(CarTVTheme.textTertiary.opacity(0.6))
        }
    }
    
    private func iconForGroup(_ group: String) -> String {
        let g = group.lowercased()
        if g.contains("movie") || g.contains("cinema") {
            return "film"
        } else if g.contains("sport") {
            return "sportscourt"
        } else if g.contains("news") {
            return "newspaper"
        } else if g.contains("series") {
            return "play.rectangle.on.rectangle"
        } else {
            return "tv"
        }
    }
}
