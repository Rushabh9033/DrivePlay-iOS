import SwiftUI

public struct OfflineMediaThumbnailView: View {
    public let item: LocalVideoItem
    public var size: CGSize
    
    @State private var thumbnail: UIImage? = nil
    
    public init(item: LocalVideoItem, size: CGSize = CGSize(width: 56, height: 40)) {
        self.item = item
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill))
                .frame(width: size.width, height: size.height)
            
            if item.isAudioOnly {
                // Audio badge
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    Image(systemName: "headphones")
                        .font(.system(size: size.height * 0.4, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .frame(width: size.width, height: size.height)
                .cornerRadius(8)
            } else if let img = thumbnail {
                // Real Video Frame Image
                ZStack {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .cornerRadius(8)
                    
                    // Translucent play icon in center
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 0.8)
                        )
                }
                .frame(width: size.width, height: size.height)
            } else {
                // Fallback while generating
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: size.height * 0.4))
                    .foregroundColor(CarTVTheme.accent.opacity(0.7))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .task(id: item.id) {
            if !item.isAudioOnly {
                let img = await LocalMediaService.shared.generateThumbnail(for: item)
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.thumbnail = img
                }
            }
        }
    }
}
