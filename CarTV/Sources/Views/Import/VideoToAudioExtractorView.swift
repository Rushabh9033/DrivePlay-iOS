import SwiftUI
import PhotosUI

public struct VideoToAudioExtractorView: View {
    @ObservedObject var extractor = AudioExtractorService.shared
    @Environment(\.dismiss) var dismiss
    
    public var preselectedVideoURL: URL?
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker: Bool = false
    @State private var customTitle: String = ""
    @State private var selectedLocalURL: URL?
    @State private var activePlayingItem: LocalVideoItem?
    
    public init(preselectedVideoURL: URL? = nil) {
        self.preselectedVideoURL = preselectedVideoURL
        _selectedLocalURL = State(initialValue: preselectedVideoURL)
        if let url = preselectedVideoURL {
            _customTitle = State(initialValue: url.deletingPathExtension().lastPathComponent)
        }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header graphic
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "headphones")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 16)
                    
                    Text("1-Tap Video-to-Audio Extractor")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(CarTVTheme.textPrimary)
                    
                    Text("Converts video lectures, sports commentary, and music clips into offline background audio. Runs 100% on-device with zero internet.")
                        .font(.system(size: 13))
                        .foregroundColor(CarTVTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                
                // Video Selection Section
                VStack(spacing: 12) {
                    if let selected = selectedLocalURL {
                        HStack(spacing: 12) {
                            Image(systemName: "video.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.lastPathComponent)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(CarTVTheme.textPrimary)
                                    .lineLimit(1)
                                Text("Selected Local Video")
                                    .font(.system(size: 11))
                                    .foregroundColor(CarTVTheme.textTertiary)
                            }
                            Spacer()
                            Button("Change") {
                                selectedLocalURL = nil
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    } else {
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                                HStack {
                                    Image(systemName: "photo.fill")
                                    Text("Pick from Photos")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(CarTVTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            
                            Button(action: { showDocumentPicker = true }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("Pick from Files")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(CarTVTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                // Progress Bar or Extraction Status
                if extractor.isExtracting {
                    VStack(spacing: 10) {
                        ProgressView(value: extractor.progress, total: 1.0)
                            .tint(.blue)
                            .padding(.horizontal, 24)
                        HStack {
                            Text(extractor.statusMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CarTVTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", extractor.progress * 100))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 8)
                }
                
                // Result Success Card
                if let extracted = extractor.lastExtractedItem {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(extracted.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(CarTVTheme.textPrimary)
                                    .lineLimit(1)
                                Text("Ready in Offline Vault • \(extracted.formattedSize) • \(extracted.formattedDuration)")
                                    .font(.system(size: 12))
                                    .foregroundColor(CarTVTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(12)
                        
                        Button(action: {
                            activePlayingItem = extracted
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Play Audio Now (Lock-Screen Ready)")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Error Card
                if let err = extractor.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // 1-Tap Extract Action Button
                // The button stays available after a successful extraction:
                // the service clears the result when a new extraction starts,
                // so the sheet can be used again and again.
                if extractor.canStartExtraction {
                    Button(action: startExtraction) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("Extract Audio Track")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canExtract ? Color.blue : Color.gray.opacity(0.4))
                        .cornerRadius(14)
                    }
                    .disabled(!canExtract)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Audio Extractor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                UniversalDocumentPickerView { pickedURL in
                    selectedLocalURL = pickedURL
                    customTitle = pickedURL.deletingPathExtension().lastPathComponent
                }
            }
            .onChange(of: selectedPhotoItem) { item in
                guard let item = item else { return }
                Task {
                    await extractor.extractAudio(from: item)
                    selectedPhotoItem = nil
                }
            }
            .sheet(item: $activePlayingItem) { item in
                OfflineVaultPlayerView(item: item, onDismiss: { activePlayingItem = nil })
            }
        }
    }
    
    private var canExtract: Bool {
        selectedLocalURL != nil || selectedPhotoItem != nil
    }
    
    private func startExtraction() {
        guard let url = selectedLocalURL else { return }
        Task {
            await extractor.extractAudio(from: url, customTitle: customTitle.isEmpty ? nil : customTitle)
        }
    }
}
