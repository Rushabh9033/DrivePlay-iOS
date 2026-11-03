import SwiftUI

public struct GroupDetailView: View {
    public let group: ChannelGroup
    @ObservedObject var playlistStore = PlaylistStore.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var healthService = SourceHealthService.shared
    
    @State private var filterQuery: String = ""
    @State private var displayCount: Int = 60
    @State private var isContentLoaded: Bool = false
    @State private var groupChannels: [Channel] = []
    
    public init(group: ChannelGroup) {
        self.group = group
    }
    
    private var filteredChannels: [Channel] {
        if filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return groupChannels
        } else {
            return groupChannels.filter {
                $0.name.localizedCaseInsensitiveContains(filterQuery)
            }
        }
    }
    
    public var body: some View {
        Group {
            if !isContentLoaded {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading \(group.name)...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else {
                List {
            if filteredChannels.isEmpty && !filterQuery.isEmpty {
                Section {
                    Text("No streams found matching \"\(filterQuery)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                Section {
                    let displayed = Array(filteredChannels.prefix(displayCount))
                    ForEach(displayed) { channel in
                    Button {
                        playbackManager.play(channel: channel, presentation: .docked)
                    } label: {
                        HStack(spacing: 12) {
                            // 1. Icon of the Video
                            videoThumbnailView(for: channel)
                            
                            // 2. Name of the Video & Metadata
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                HStack(spacing: 6) {
                                    Text(channel.resolutionLabel.isEmpty ? "HD" : channel.resolutionLabel)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.blue.opacity(0.18))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                    
                                    Text(channel.groupTitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer(minLength: 8)
                            
                            // 3. Real-time Stream Diagnostic
                            streamDiagnosticBadge(for: channel)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            playlistStore.toggleFavorite(for: channel)
                            // This list is a snapshot of the channel list, so the
                            // swipe label would keep saying "Favorite" otherwise.
                            if let idx = groupChannels.firstIndex(where: { $0.id == channel.id }) {
                                groupChannels[idx].isFavorite.toggle()
                            }
                        } label: {
                            Label(
                                channel.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: channel.isFavorite ? "star.slash" : "star.fill"
                            )
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            playbackManager.play(channel: channel, presentation: .fullscreen)
                        } label: {
                            Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .tint(.blue)
                    }
                }
                
                if displayCount < filteredChannels.count {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Text("Loading more videos (\(min(displayCount, filteredChannels.count)) of \(filteredChannels.count))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .onAppear {
                        displayCount = min(displayCount + 60, filteredChannels.count)
                    }
                }
            } header: {
                HStack {
                    Text("\(filteredChannels.count) Videos")
                    Spacer()
                    Text("Real-Time Diagnostic")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filterQuery, prompt: "Search in \(group.name)")
        .onChange(of: filterQuery) { _ in
            displayCount = 60
        }
        .task {
            guard !isContentLoaded else { return }
            try? await Task.sleep(nanoseconds: 30_000_000)
            let chs = group.channels
            await MainActor.run {
                self.groupChannels = chs
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.isContentLoaded = true
                }
            }
            
            // Lightweight initial telemetry probe for first batch only
            let channelsToProbe = Array(chs.prefix(25))
            Task.detached(priority: .background) {
                await SourceHealthService.shared.probeChannels(channelsToProbe)
            }
        }
    }
    
    // MARK: - Video Thumbnail View
    @ViewBuilder
    private func videoThumbnailView(for channel: Channel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill))
                .frame(width: 48, height: 48)
            
            if let logoURL = channel.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 42, height: 42)
                            .cornerRadius(6)
                    case .failure, .empty:
                        fallbackIcon(for: channel)
                    @unknown default:
                        fallbackIcon(for: channel)
                    }
                }
            } else {
                fallbackIcon(for: channel)
            }
        }
    }
    
    @ViewBuilder
    private func fallbackIcon(for channel: Channel) -> some View {
        let isMovie = channel.groupTitle.localizedCaseInsensitiveContains("movie") || channel.groupTitle.localizedCaseInsensitiveContains("film")
        let isSports = channel.groupTitle.localizedCaseInsensitiveContains("sport")
        let isLive = channel.groupTitle.localizedCaseInsensitiveContains("live")
        
        Image(systemName: isMovie ? "film.fill" : (isSports ? "sportscourt.fill" : (isLive ? "tv.fill" : "play.rectangle.fill")))
            .font(.system(size: 20))
            .foregroundColor(isMovie ? .purple : (isSports ? .green : .accentColor))
    }
    
    // MARK: - Real-Time Stream Diagnostic Badge
    @ViewBuilder
    private func streamDiagnosticBadge(for channel: Channel) -> some View {
        if healthService.checkingChannelIds.contains(channel.id) {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Testing...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(6)
        } else if let health = healthService.healthMap[channel.id] {
            HStack(spacing: 5) {
                Circle()
                    .fill(diagnosticColor(for: health.status))
                    .frame(width: 7, height: 7)
                
                Text(health.status == .offline ? "Offline" : "\(health.resolution) • \(health.latencyMs)ms")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(diagnosticColor(for: health.status))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(diagnosticColor(for: health.status).opacity(0.12))
            .cornerRadius(6)
        } else {
            // Unprobed state: automatically triggers probe and shows neutral checking indicator
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                
                Text("Checking...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(6)
            .task {
                await healthService.probeChannel(channel)
            }
        }
    }
    
    private func diagnosticColor(for status: StreamHealthInfo.Status) -> Color {
        switch status {
        case .excellent, .good:
            return .green
        case .fair:
            return .yellow
        case .poor, .offline:
            return .red
        case .testing:
            return .gray
        }
    }
}
