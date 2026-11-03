import Foundation
import AVFoundation
import SwiftUI
import PhotosUI
import CoreTransferable

@MainActor
public final class AudioExtractorService: ObservableObject {
    public static let shared = AudioExtractorService()
    
    @Published public var isExtracting: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = ""
    @Published public var lastExtractedItem: LocalVideoItem?
    @Published public var errorMessage: String?
    
    private var progressTimer: Timer?
    
    public init() {}
    
    /// Extract audio from a local video file URL (from Files or Offline Vault)
    public func extractAudio(from videoURL: URL, customTitle: String? = nil) async {
        isExtracting = true
        progress = 0.0
        statusMessage = "Analyzing video stream..."
        errorMessage = nil
        lastExtractedItem = nil
        
        let asset = AVURLAsset(url: videoURL)
        await performExtraction(asset: asset, defaultTitle: customTitle ?? videoURL.deletingPathExtension().lastPathComponent)
    }
    
    /// Extract audio from a PhotosPickerItem
    public func extractAudio(from photoItem: PhotosPickerItem) async {
        isExtracting = true
        progress = 0.0
        statusMessage = "Loading video from Photos..."
        errorMessage = nil
        lastExtractedItem = nil
        
        do {
            guard let movie = try await photoItem.loadTransferable(type: VideoTransferable.self) else {
                throw NSError(domain: "AudioExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video file from library."])
            }
            let asset = AVURLAsset(url: movie.url)
            await performExtraction(asset: asset, defaultTitle: "Extracted_Audio_\(Date().formatted(.dateTime.month().day().hour().minute()))")
            // Clean up temporary photo transfer file
            try? FileManager.default.removeItem(at: movie.url)
        } catch {
            isExtracting = false
            errorMessage = error.localizedDescription
        }
    }
    
    private func performExtraction(asset: AVURLAsset, defaultTitle: String) async {
        statusMessage = "Extracting high-fidelity audio..."
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            isExtracting = false
            errorMessage = "Audio extraction preset is not supported for this media."
            return
        }
        
        let sanitizedTitle = defaultTitle.replacingOccurrences(of: "/", with: "-")
        let outputFileName = "\(sanitizedTitle).m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Progress monitor timer
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.progress = Double(exportSession.progress)
            }
        }
        self.progressTimer = timer
        
        await exportSession.export()
        
        timer.invalidate()
        self.progressTimer = nil
        
        if exportSession.status == .completed {
            self.progress = 1.0
            self.statusMessage = "Saving to Offline Vault..."
            let item = await LocalMediaService.shared.addExtractedAudio(fileURL: outputURL, title: sanitizedTitle)
            self.lastExtractedItem = item
            self.statusMessage = "Extraction Complete!"
            self.isExtracting = false
        } else {
            self.isExtracting = false
            self.errorMessage = exportSession.error?.localizedDescription ?? "Extraction failed."
        }
    }
}

