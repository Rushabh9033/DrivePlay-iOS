import SwiftUI

public struct PlaylistSwitchSheet: View {
    public let sources: [PlaylistSource]
    public let currentSourceId: UUID
    public let onSelect: (PlaylistSource) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var searchQuery: String = ""
    
    public init(
        sources: [PlaylistSource],
        currentSourceId: UUID,
        onSelect: @escaping (PlaylistSource) -> Void
    ) {
        self.sources = sources
        self.currentSourceId = currentSourceId
        self.onSelect = onSelect
    }
    
    private var filteredSources: [PlaylistSource] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return sources
        }
        return sources.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.type.rawValue.localizedCaseInsensitiveContains(q)
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                    
                    TextField("Search playlists...", text: $searchQuery)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemFill))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                Divider()
                
                // Playlist List
                List {
                    if filteredSources.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No Playlists Found")
                                    .font(.headline)
                                Text("No source matches \"\(searchQuery)\"")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        Section("All Playlists (\(filteredSources.count))") {
                            ForEach(filteredSources) { source in
                                Button {
                                    onSelect(source)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(source.id == currentSourceId ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemFill))
                                                .frame(width: 44, height: 44)
                                            
                                            Image(systemName: source.type.iconName)
                                                .font(.system(size: 20))
                                                .foregroundColor(source.id == currentSourceId ? .accentColor : .secondary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(source.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.primary)
                                            
                                            HStack(spacing: 6) {
                                                Text(source.type.rawValue)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.blue.opacity(0.18))
                                                    .foregroundColor(.blue)
                                                    .cornerRadius(3)
                                                
                                                let streamCount = PlaylistStore.shared.channels(for: source.id).count
                                                Text("\(streamCount) Streams")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if source.id == currentSourceId {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.green)
                                                Text("Active")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Switch Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
