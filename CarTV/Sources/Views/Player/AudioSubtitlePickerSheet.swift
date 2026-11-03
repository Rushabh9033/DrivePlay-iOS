import SwiftUI

public struct AudioSubtitlePickerSheet: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    @Environment(\.dismiss) var dismiss
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Audio Tracks")) {
                    ForEach(playbackManager.audioTracks, id: \.self) { track in
                        HStack {
                            Text(track)
                            Spacer()
                            if playbackManager.selectedAudioTrack == track {
                                Image(systemName: "checkmark")
                                    .foregroundColor(CarTVTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playbackManager.selectedAudioTrack = track
                        }
                    }
                }
                
                Section(header: Text("Subtitles")) {
                    ForEach(playbackManager.subtitleTracks, id: \.self) { track in
                        HStack {
                            Text(track)
                            Spacer()
                            if playbackManager.selectedSubtitleTrack == track {
                                Image(systemName: "checkmark")
                                    .foregroundColor(CarTVTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playbackManager.selectedSubtitleTrack = track
                        }
                    }
                }
            }
            .navigationTitle("Audio & Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
