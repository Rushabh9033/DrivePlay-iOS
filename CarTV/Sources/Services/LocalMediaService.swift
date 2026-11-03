import Foundation
import AVFoundation
import UIKit

@MainActor
public final class LocalMediaService: ObservableObject {
    public static let shared = LocalMediaService()
    
    @Published public var localVideos: [LocalVideoItem] = []
    
    private let fileManager = FileManager.default
    private var storageDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosDir = docs.appendingPathComponent("ImportedVideos", isDirectory: true)
        if !fileManager.fileExists(atPath: videosDir.path) {
            try? fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)
        }
        return videosDir
    }
    
    public init() {
        loadStoredVideos()
    }
    
    public func importVideoFile(from sourceURL: URL) async throws -> LocalVideoItem {
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        // The stored name is prefixed with a fresh id. Two imports with the same
        // original filename (say `clip.mp4` from two different folders) used to
        // overwrite each other, leaving two vault entries pointing at one file.
        let id = UUID()
        let destinationURL = storageDirectory
            .appendingPathComponent("\(id.uuidString)_\(sourceURL.lastPathComponent)")

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        // Extract metadata
        let attr = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attr[.size] as? Int64) ?? 0
        let asset = AVURLAsset(url: destinationURL)
        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0

        let ext = destinationURL.pathExtension.lowercased()
        let audioExts = ["mp3", "m4a", "flac", "wav", "aac", "aiff"]
        let isAudio = audioExts.contains(ext)

        let item = LocalVideoItem(
            id: id,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            relativePath: destinationURL.lastPathComponent,
            fileSize: fileSize,
            duration: durationSeconds,
            dateAdded: Date(),
            resolution: isAudio ? "AUDIO" : "1080P",
            isAudioOnly: isAudio
        )

        localVideos.insert(item, at: 0)
        saveIndex()
        return item
    }

    public func addExtractedAudio(fileURL: URL, title: String) async -> LocalVideoItem {
        let id = UUID()
        let destinationURL = storageDirectory
            .appendingPathComponent("\(id.uuidString)_\(fileURL.lastPathComponent)")
        if fileURL != destinationURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try? fileManager.copyItem(at: fileURL, to: destinationURL)
        }

        let attr = (try? fileManager.attributesOfItem(atPath: destinationURL.path)) ?? [:]
        let fileSize = (attr[.size] as? Int64) ?? 0
        let asset = AVURLAsset(url: destinationURL)
        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0

        let item = LocalVideoItem(
            id: id,
            title: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
            relativePath: destinationURL.lastPathComponent,
            fileSize: fileSize,
            duration: durationSeconds,
            dateAdded: Date(),
            resolution: "AUDIO",
            isAudioOnly: true
        )

        localVideos.insert(item, at: 0)
        saveIndex()
        return item
    }
    
    public func getFileURL(for item: LocalVideoItem) -> URL {
        return storageDirectory.appendingPathComponent(item.relativePath)
    }
    
    public func thumbnailURL(for item: LocalVideoItem) -> URL {
        return storageDirectory.appendingPathComponent("\(item.id.uuidString)_thumb.jpg")
    }
    
    public func generateThumbnail(for item: LocalVideoItem) async -> UIImage? {
        guard !item.isAudioOnly else { return nil }
        let thumbURL = thumbnailURL(for: item)
        
        // Return existing cached thumbnail immediately if present
        if fileManager.fileExists(atPath: thumbURL.path),
           let data = try? Data(contentsOf: thumbURL),
           let cachedImg = UIImage(data: data) {
            return cachedImg
        }
        
        let fileURL = getFileURL(for: item)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        return await Task.detached(priority: .userInitiated) { [thumbURL, fileURL] () -> UIImage? in
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 240)
            
            let targetSeconds = min(1.0, max(0.1, item.duration / 3))
            let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
            
            if let cgImage = try? generator.copyCGImage(at: targetTime, actualTime: nil) {
                let img = UIImage(cgImage: cgImage)
                if let jpeg = img.jpegData(compressionQuality: 0.75) {
                    try? jpeg.write(to: thumbURL)
                }
                return img
            } else if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let img = UIImage(cgImage: cgImage)
                if let jpeg = img.jpegData(compressionQuality: 0.75) {
                    try? jpeg.write(to: thumbURL)
                }
                return img
            }
            return nil
        }.value
    }
    
    public func deleteVideo(item: LocalVideoItem) {
        let url = getFileURL(for: item)
        try? fileManager.removeItem(at: url)
        let thumb = thumbnailURL(for: item)
        try? fileManager.removeItem(at: thumb)
        localVideos.removeAll { $0.id == item.id }
        saveIndex()
    }
    
    private func saveIndex() {
        let indexURL = storageDirectory.appendingPathComponent("index.json")
        if let data = try? JSONEncoder().encode(localVideos) {
            // Atomic: a non-atomic write that is interrupted leaves a truncated file,
            // and the whole vault then fails to load — every import looked lost.
            try? data.write(to: indexURL, options: .atomic)
        }
    }
    
    private func loadStoredVideos() {
        let indexURL = storageDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let items = try? JSONDecoder().decode([LocalVideoItem].self, from: data) {
            self.localVideos = items
        }
    }
}
