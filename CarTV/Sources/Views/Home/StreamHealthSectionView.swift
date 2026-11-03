import SwiftUI

public struct StreamHealthSectionView: View {
    @ObservedObject var healthService = SourceHealthService.shared
    @ObservedObject var playlistStore = PlaylistStore.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    
    public let onAddPlaylist: () -> Void
    
    public init(onAddPlaylist: @escaping () -> Void) {
        self.onAddPlaylist = onAddPlaylist
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Live Pulse indicator
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("LIVE STREAM TELEMETRY")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Real-Time")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 2)
            
            // Channels Telemetry
            if playlistStore.channels.isEmpty {
                Text("No channels added yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(playlistStore.channels.prefix(5)) { channel in
                    let health = healthService.getHealth(for: channel.id)
                    let isChecking = healthService.checkingChannelIds.contains(channel.id)
                    
                    Button(action: {
                        playbackManager.play(channel: channel, presentation: .docked)
                    }) {
                        HStack(spacing: 12) {
                            if isChecking {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16)
                            } else {
                                Circle()
                                    .fill(statusColor(for: health?.status ?? .good))
                                    .frame(width: 9, height: 9)
                            }
                            
                            Text(channel.name)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if let h = health {
                                Text("\(h.resolution) • \(h.latencyMs)ms")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(.secondary)
                            } else {
                                Text(channel.resolutionLabel.isEmpty ? "1080p" : channel.resolutionLabel)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func statusColor(for status: StreamHealthInfo.Status) -> Color {
        switch status {
        case .excellent, .good: return .green
        case .fair: return .yellow
        case .poor, .offline: return .red
        case .testing: return .gray
        }
    }
}
