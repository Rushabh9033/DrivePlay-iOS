import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct UniversalOfflineVaultView: View {
    @ObservedObject var localMediaService = LocalMediaService.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    
    @State private var filterMode: FilterMode = .all
    @State private var searchQuery: String = ""
    @State private var showDocumentPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var activePlayingItem: LocalVideoItem? = nil
    @State private var showExtractorSheet: Bool = false
    @State private var extractorVideoURL: URL? = nil
    
    public enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case video = "Videos"
        case audio = "Audio"
        public var id: String { rawValue }
    }
    
    public init() {}
    
    private var filteredItems: [LocalVideoItem] {
        var items = localMediaService.localVideos
        
        switch filterMode {
        case .all:
            break
        case .video:
            items = items.filter { !$0.isAudioOnly }
        case .audio:
            items = items.filter { $0.isAudioOnly }
        }
        
        if !searchQuery.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
        
        return items
    }
    
    private var totalSizeString: String {
        let total = localMediaService.localVideos.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    public var body: some View {
        List {
            // Segmented Filter
            Section {
                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Items List
            if filteredItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Offline Media",
                        systemImage: "externaldrive.badge.icloud",
                        description: Text("Import MKV, MP4, FLAC, or MP3 files from Files or Photos to play anytime offline.")
                    )
                    
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Import from Files", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("Storage: \(totalSizeString) (\(filteredItems.count) items)")) {
                    ForEach(filteredItems) { item in
                        Button {
                            if item.isAudioOnly {
                                activePlayingItem = item
                            } else {
                                playbackManager.playOffline(item: item, inLandscape: true)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                OfflineMediaThumbnailView(item: item, size: CGSize(width: 58, height: 40))
                                
                                VStack(alignment: .leading, spacing: 3) {
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
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                localMediaService.deleteVideo(item: item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !item.isAudioOnly {
                                Button {
                                    let url = localMediaService.getFileURL(for: item)
                                    extractorVideoURL = url
                                    showExtractorSheet = true
                                } label: {
                                    Label("To MP3", systemImage: "headphones")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Offline Vault")
        .searchable(text: $searchQuery, prompt: "Search files")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Import from Files", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        showExtractorSheet = true
                    } label: {
                        Label("Audio Extractor Tool", systemImage: "headphones")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(item: $activePlayingItem) { item in
            OfflineVaultPlayerView(item: item, onDismiss: { activePlayingItem = nil })
        }
        .sheet(isPresented: $showDocumentPicker) {
            UniversalDocumentPickerView { selectedURL in
                Task {
                    _ = try? await localMediaService.importVideoFile(from: selectedURL)
                }
            }
        }
        .sheet(isPresented: $showExtractorSheet) {
            VideoToAudioExtractorView(preselectedVideoURL: extractorVideoURL)
        }
    }
}

public struct UniversalDocumentPickerView: UIViewControllerRepresentable {
    public let onPick: (URL) -> Void
    
    public init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [
            .movie,
            .video,
            .mpeg4Movie,
            .quickTimeMovie
        ]
        if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
        if let avi = UTType(filenameExtension: "avi") { types.append(avi) }
        if let webm = UTType(filenameExtension: "webm") { types.append(webm) }
        if let ts = UTType(filenameExtension: "ts") { types.append(ts) }
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let first = urls.first else { return }
            onPick(first)
        }
    }
}
