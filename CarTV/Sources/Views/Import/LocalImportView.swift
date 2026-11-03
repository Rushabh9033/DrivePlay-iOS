import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct LocalImportView: View {
    @ObservedObject var localMediaService = LocalMediaService.shared
    @ObservedObject var playbackManager = PlaybackManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var searchQuery: String = ""
    @State private var showDocumentPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header (Matching Shot 04: "Recent Items" and Cancel button)
                HStack {
                    Spacer()
                    Text("Recent Items")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(CarTVTheme.textPrimary)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16))
                    .foregroundColor(Color(UIColor.systemRed))
                    .padding(.trailing, 16)
                }
                .padding(.vertical, 12)
                
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(CarTVTheme.textSecondary)
                    TextField("Search", text: $searchQuery)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Action buttons: Pick from Files & Pick from Photos
                        HStack(spacing: 12) {
                            Button(action: { showDocumentPicker = true }) {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                    Text("Files App")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            
                            PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                                HStack {
                                    Image(systemName: "photo.badge.plus")
                                    Text("Photos")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Recent items grid
                        if localMediaService.localVideos.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(CarTVTheme.textTertiary)
                                Text("No local videos imported yet")
                                    .font(.system(size: 15))
                                    .foregroundColor(CarTVTheme.textSecondary)
                                Text("Import MP4, MKV, or MOV files from Files or Photos to play offline.")
                                    .font(.system(size: 13))
                                    .foregroundColor(CarTVTheme.textTertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(filteredVideos) { video in
                                    Button(action: {
                                        playLocalVideo(video)
                                    }) {
                                        VStack(alignment: .center, spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(UIColor.secondarySystemFill))
                                                    .aspectRatio(1, contentMode: .fit)
                                                
                                                Image(systemName: "film")
                                                    .font(.system(size: 26))
                                                    .foregroundColor(CarTVTheme.textSecondary)
                                            }
                                            
                                            Text(video.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(CarTVTheme.textPrimary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                            
                                            Text(video.formattedDate)
                                                .font(.system(size: 10))
                                                .foregroundColor(CarTVTheme.textTertiary)
                                            
                                            Text(video.formattedSize)
                                                .font(.system(size: 10))
                                                .foregroundColor(CarTVTheme.textTertiary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Blue Folder Shortcuts row (Matching Shot 04 bottom)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Folders")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(CarTVTheme.textSecondary)
                                .padding(.horizontal, 16)
                            
                            HStack(spacing: 16) {
                                folderShortcut(name: "Movie Files", count: "\(filteredVideos.count) items")
                                folderShortcut(name: "Camera Roll", count: "Videos")
                                folderShortcut(name: "Downloads", count: "Files")
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 30)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView { url in
                    Task {
                        _ = try? await localMediaService.importVideoFile(from: url)
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                        // The service removes the temporary copy when it is
                        // done with it — otherwise every photo imported leaves
                        // a full-size copy behind in the temp folder.
                        _ = try? await localMediaService.importTemporaryVideo(from: movie.url)
                    }
                }
            }
        }
    }
    
    private func folderShortcut(name: String, count: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 44))
                .foregroundColor(Color(red: 0.18, green: 0.65, blue: 0.95))
            
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CarTVTheme.textPrimary)
                .lineLimit(1)
            
            Text(count)
                .font(.system(size: 10))
                .foregroundColor(CarTVTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var filteredVideos: [LocalVideoItem] {
        if searchQuery.isEmpty {
            return localMediaService.localVideos
        } else {
            return localMediaService.localVideos.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
    }
    
    private func playLocalVideo(_ item: LocalVideoItem) {
        let url = localMediaService.getFileURL(for: item)
        let channel = Channel(
            name: item.title,
            streamURL: url,
            groupTitle: "Local Videos",
            resolutionLabel: item.resolution
        )
        dismiss()
        playbackManager.play(channel: channel, presentation: .docked)
    }
}

public struct DocumentPickerView: UIViewControllerRepresentable {
    public let onPick: (URL) -> Void
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
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
            if let first = urls.first {
                onPick(first)
            }
        }
    }
}

public struct VideoTransferable: Transferable {
    public let url: URL
    
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return VideoTransferable(url: temp)
        }
    }
}
