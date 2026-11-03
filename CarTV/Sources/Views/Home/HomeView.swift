import SwiftUI

public struct HomeView: View {
    @ObservedObject var playlistStore = PlaylistStore.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var hud = SatelliteHUDService.shared
    @ObservedObject var localMedia = LocalMediaService.shared
    
    private enum ActiveHomeSheet: Identifiable {
        case addSource
        case offlinePlayer(LocalVideoItem)
        case voiceSearch

        var id: String {
            switch self {
            case .addSource:
                return "addSource"
            case .offlinePlayer(let item):
                return "offlinePlayer_\(item.id.uuidString)"
            case .voiceSearch:
                return "voiceSearch"
            }
        }
    }
    
    @State private var activeSheet: ActiveHomeSheet? = nil
    
    public init() {}
    
    public var body: some View {
        List {
            // Section 1: Satellite Cockpit Telemetry
            cockpitTelemetrySection
            
            // Section 2: Saved Offline Media (if available)
            if !localMedia.localVideos.isEmpty {
                offlineMediaSection
            }
            
            // Search Results (when searching)
            if !playlistStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsSection
            }
            
            // Section 3: Playlists & Media Sources (SOURCE-WISE SEPARATION)
            sourcesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("DrivePlay")
        .searchable(text: $playlistStore.searchQuery, prompt: "Search channels and videos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .addSource
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .voiceSearch
                } label: {
                    Image(systemName: "mic.fill")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addSource:
                AddSourceSheet()
            case .offlinePlayer(let item):
                OfflineVaultPlayerView(item: item, onDismiss: {
                    activeSheet = nil
                })
            case .voiceSearch:
                VoiceSearchOverlayView(onDismiss: {
                    activeSheet = nil
                }, onResult: { transcript in
                    playIfVoiceMatches(transcript)
                })
            }
        }
    }

    /// Plays the channel a spoken phrase names. The phrase is matched against channel
    /// names first, then category names.
    private func playIfVoiceMatches(_ transcript: String) {
        let query = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let channels = playlistStore.channels
        guard let match = channels.first(where: { $0.name.localizedCaseInsensitiveContains(query) })
                ?? channels.first(where: { $0.groupTitle.localizedCaseInsensitiveContains(query) })
        else { return }
        activeSheet = nil
        playbackManager.play(channel: match, presentation: .docked)
    }
    
    // MARK: - Cockpit Telemetry Section
    private var cockpitTelemetrySection: some View {
        Section {
            DigitalClusterCardView(hud: hud)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Cockpit Telemetry")
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.95, blue: 0.6))
                        .frame(width: 6, height: 6)
                    Text("DIGITAL CLUSTER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.6))
                }
            }
        }
    }
    
    // MARK: - Offline Media Section
    private var offlineMediaSection: some View {
        Section("Saved Offline Media (\(localMedia.localVideos.count))") {
            ForEach(localMedia.localVideos.prefix(5)) { item in
                Button {
                    if item.isAudioOnly {
                        activeSheet = .offlinePlayer(item)
                    } else {
                        playbackManager.playOffline(item: item, inLandscape: true)
                    }
                } label: {
                    offlineMediaRow(item)
                }
                .buttonStyle(.plain)
            }
            
            NavigationLink(destination: UniversalOfflineVaultView()) {
                Text("View All in Offline Vault")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
    
    @ViewBuilder
    private func offlineMediaRow(_ item: LocalVideoItem) -> some View {
        HStack(spacing: 12) {
            OfflineMediaThumbnailView(item: item, size: CGSize(width: 52, height: 36))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.formatBadge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(UIColor.secondarySystemFill))
                        .cornerRadius(3)
                    
                    Text("\(item.formattedDuration) • \(item.formattedSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    // MARK: - Search Results Section
    private var searchResultsSection: some View {
        let matches = playlistStore.channels.filter {
            $0.name.localizedCaseInsensitiveContains(playlistStore.searchQuery) ||
            $0.groupTitle.localizedCaseInsensitiveContains(playlistStore.searchQuery)
        }
        
        return Section("Search Results (\(matches.count))") {
            if matches.isEmpty {
                Text("No streams found matching \"\(playlistStore.searchQuery)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(matches) { channel in
                    Button {
                        playbackManager.play(channel: channel, presentation: .docked)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(channel.groupTitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(channel.resolutionLabel)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.18))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Media Sources Section (SOURCE-WISE SEPARATION)
    private var sourcesSection: some View {
        Section {
            if playlistStore.sources.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 42))
                        .foregroundColor(.accentColor)
                        .padding(.top, 8)
                    
                    Text("No Media Sources Added")
                        .font(.headline)
                    
                    Text("Add your M3U / M3U8 playlists, Xtream Codes, Jellyfin, or Plex servers to start watching.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    
                    Button {
                        activeSheet = .addSource
                    } label: {
                        Label("Add Media Source", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(playlistStore.sources) { source in
                    let count = playlistStore.channels(for: source.id).count
                    NavigationLink(destination: SourceDetailView(source: source)) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(sourceColor(for: source.type).opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: source.type.iconName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(sourceColor(for: source.type))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                HStack(spacing: 6) {
                                    Text(source.type.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(UIColor.secondarySystemFill))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(3)
                                    
                                    Text("\(count) Streams")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            playlistStore.removeSource(source)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Playlists & Media Sources (\(playlistStore.sources.count))")
                Spacer()
                Button {
                    activeSheet = .addSource
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
    }
    
    private func sourceColor(for type: SourceType) -> Color {
        switch type {
        case .m3u: return .blue
        case .xtream: return .orange
        case .jellyfin: return .purple
        case .emby: return .green
        case .plex: return .yellow
        case .local: return .teal
        }
    }
}
