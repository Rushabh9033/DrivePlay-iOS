import SwiftUI

public struct SourceDetailView: View {
    public let initialSource: PlaylistSource
    @State private var currentSource: PlaylistSource
    @State private var isShowingPlaylistSwitcher: Bool = false
    
    @ObservedObject var playlistStore = PlaylistStore.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    @ObservedObject var healthService = SourceHealthService.shared
    @ObservedObject var historyStore = WatchHistoryStore.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var filterQuery: String = ""
    @State private var selectedCategory: String = "All"
    @State private var displayCount: Int = 60
    
    // Asynchronous deferred loading: screen opens instantly, content loads smoothly after appearance
    @State private var isContentLoaded: Bool = false
    @State private var sourceChannels: [Channel] = []
    @State private var sourceGroups: [ChannelGroup] = []
    @State private var playlistHistory: [WatchedItem] = []
    
    public init(source: PlaylistSource) {
        self.initialSource = source
        self._currentSource = State(initialValue: source)
    }
    
    private var directMatchingChannels: [Channel] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return sourceChannels.filter {
            $0.name.localizedCaseInsensitiveContains(q)
        }
    }
    
    private var categoryFilteredChannels: [Channel] {
        var list = (selectedCategory == "All") ? sourceChannels : sourceChannels.filter { $0.groupTitle == selectedCategory }
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }
        return list
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !isContentLoaded {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading \(currentSource.name)...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else {
                // Category Filter Pills Bar (All, Movies, News, Sports, etc.)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryPill(title: "All")
                        ForEach(sourceGroups) { group in
                            categoryPill(title: group.name)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(UIColor.systemBackground))
            
            // Search Option Inside Playlist (Positioned Below Filter Pills)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField(selectedCategory == "All" ? "Search in \(currentSource.name)..." : "Search in \(selectedCategory)...", text: $filterQuery)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: filterQuery) { _ in
                        displayCount = 60
                    }
                
                if !filterQuery.isEmpty {
                    Button {
                        filterQuery = ""
                        displayCount = 60
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(UIColor.secondarySystemFill))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground))
            
            Divider()
            
            List {
                // When Search Query is active in "All"
                if !filterQuery.isEmpty && selectedCategory == "All" {
                    Section("Matching Streams (\(directMatchingChannels.count))") {
                        if directMatchingChannels.isEmpty {
                            Text("No streams found matching \"\(filterQuery)\"")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            let displayed = Array(directMatchingChannels.prefix(displayCount))
                            ForEach(displayed) { channel in
                                channelListRow(channel)
                            }
                            if displayCount < directMatchingChannels.count {
                                HStack {
                                    Spacer()
                                    ProgressView().scaleEffect(0.8)
                                    Text("Loading more results...")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .onAppear {
                                    displayCount = min(displayCount + 60, directMatchingChannels.count)
                                }
                            }
                        }
                    }
                } else if selectedCategory != "All" {
                    // Category-Filtered Stream List View (Icon + Name + Real-Time Diagnostic)
                    Section("\(selectedCategory) (\(categoryFilteredChannels.count))") {
                        if categoryFilteredChannels.isEmpty {
                            Text("No videos found in \(selectedCategory)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            let displayed = Array(categoryFilteredChannels.prefix(displayCount))
                            ForEach(displayed) { channel in
                                channelListRow(channel)
                            }
                            if displayCount < categoryFilteredChannels.count {
                                HStack {
                                    Spacer()
                                    ProgressView().scaleEffect(0.8)
                                    Text("Loading more (\(displayed.count) of \(categoryFilteredChannels.count))...")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .onAppear {
                                    displayCount = min(displayCount + 60, categoryFilteredChannels.count)
                                }
                            }
                        }
                    }
                } else {
                    // "All" View: Playlist History and Category Folders
                    
                    // 1. Playlist-Specific Watch History (Last 3 watched items)
                    if !playlistHistory.isEmpty {
                        Section {
                            ForEach(playlistHistory.prefix(3)) { item in
                                Button {
                                    let ch = Channel(
                                        id: item.channelId,
                                        name: item.name,
                                        streamURL: item.streamURL,
                                        groupTitle: item.groupTitle,
                                        logoURL: item.logoURL,
                                        sourceId: item.sourceId,
                                        resolutionLabel: item.resolutionLabel
                                    )
                                    playbackManager.play(channel: ch, presentation: .docked)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.12))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 18))
                                                .foregroundColor(.accentColor)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                Text(item.resolutionLabel)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.18))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(3)
                                                
                                                Text(item.groupTitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.accentColor)
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            HStack {
                                Text("Recently Watched in \(currentSource.name)")
                                Spacer()
                                Button("Clear") {
                                    historyStore.clearHistory(for: currentSource.id)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 2. Category Folders
                    Section("Categories (\(sourceGroups.count))") {
                        ForEach(sourceGroups) { group in
                            Button {
                                withAnimation {
                                    selectedCategory = group.name
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    categoryIcon(for: group.name)
                                        .frame(width: 28)
                                    
                                    Text(group.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(group.channels.count)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(Color(UIColor.tertiaryLabel))
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // 3. Source Management
                    Section {
                        Button(role: .destructive) {
                            playlistStore.removeSource(currentSource)
                            dismiss()
                        } label: {
                            Label("Remove This Media Source", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(currentSource.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingPlaylistSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
                .accessibilityLabel("Switch Playlist")
            }
        }
        .sheet(isPresented: $isShowingPlaylistSwitcher) {
            PlaylistSwitchSheet(
                sources: playlistStore.sources,
                currentSourceId: currentSource.id,
                onSelect: { newSource in
                    switchSource(to: newSource)
                }
            )
        }
        .task {
            guard !isContentLoaded else { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
            loadData(for: currentSource)
        }
    }
    
    // MARK: - Playlist Switch & Load
    private func switchSource(to newSource: PlaylistSource) {
        guard newSource.id != currentSource.id else { return }
        withAnimation {
            currentSource = newSource
            isContentLoaded = false
            selectedCategory = "All"
            filterQuery = ""
            displayCount = 60
        }
        loadData(for: newSource)
    }
    
    private func loadData(for src: PlaylistSource) {
        Task {
            let chs = playlistStore.channels(for: src.id)
            let grps = playlistStore.groups(for: src.id)
            let hist = historyStore.history(for: src.id)
            
            await MainActor.run {
                self.sourceChannels = chs
                self.sourceGroups = grps
                self.playlistHistory = hist
                withAnimation(.easeInOut(duration: 0.2)) {
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
    
    // MARK: - Category Pill Button
    private func categoryPill(title: String) -> some View {
        let isSelected = selectedCategory == title
        return Button(action: {
            withAnimation(.spring(response: 0.3)) {
                selectedCategory = title
                displayCount = 60
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Channel List Row (Icon + Name + Real-Time Diagnostic)
    @ViewBuilder
    private func channelListRow(_ channel: Channel) -> some View {
        Button {
            playbackManager.play(channel: channel, presentation: .docked)
        } label: {
            HStack(spacing: 12) {
                // 1. Icon of the Video
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: 46, height: 46)
                    
                    if let logoURL = channel.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(6)
                            case .failure, .empty:
                                categoryIcon(for: channel.groupTitle)
                            @unknown default:
                                categoryIcon(for: channel.groupTitle)
                            }
                        }
                    } else {
                        categoryIcon(for: channel.groupTitle)
                    }
                }
                
                // 2. Name & Group Title
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Stream Diagnostic Badge
    @ViewBuilder
    private func streamDiagnosticBadge(for channel: Channel) -> some View {
        let isCurrentPlaying = (playbackManager.currentChannel?.id == channel.id && playbackManager.isPlaying)
        let health = healthService.getHealth(for: channel.id)
        
        HStack(spacing: 4) {
            if isCurrentPlaying {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Playing • 14ms")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundColor(.green)
            } else if let h = health {
                Circle()
                    .fill(colorForStatus(h.status))
                    .frame(width: 7, height: 7)
                Text(h.labelText)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundColor(colorForStatus(h.status))
            } else if healthService.checkingChannelIds.contains(channel.id) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Testing...")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            } else {
                // Auto-probes channel on row display
                ProgressView()
                    .scaleEffect(0.6)
                Text("Checking...")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(UIColor.tertiarySystemFill))
        .cornerRadius(6)
        .task {
            if health == nil && !isCurrentPlaying {
                await healthService.probeChannel(channel)
            }
        }
    }
    
    private func colorForStatus(_ status: StreamHealthInfo.Status) -> Color {
        switch status {
        case .excellent, .good: return .green
        case .fair: return .yellow
        case .poor, .offline: return .red
        case .testing: return .gray
        }
    }
    
    @ViewBuilder
    private func categoryIcon(for name: String) -> some View {
        let lower = name.lowercased()
        if lower.contains("movie") || lower.contains("film") || lower.contains("cinema") {
            Image(systemName: "film.fill")
                .foregroundColor(.purple)
        } else if lower.contains("sport") {
            Image(systemName: "sportscourt.fill")
                .foregroundColor(.green)
        } else if lower.contains("live") || lower.contains("tv") {
            Image(systemName: "tv.fill")
                .foregroundColor(.blue)
        } else if lower.contains("series") || lower.contains("show") {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .foregroundColor(.orange)
        } else if lower.contains("news") {
            Image(systemName: "newspaper.fill")
                .foregroundColor(.red)
        } else {
            Image(systemName: "folder.fill")
                .foregroundColor(.secondary)
        }
    }
}
