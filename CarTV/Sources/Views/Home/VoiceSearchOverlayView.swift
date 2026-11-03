import SwiftUI

public struct VoiceSearchOverlayView: View {
    public let onDismiss: () -> Void
    /// Called with every partial transcript, so the caller can match a channel live.
    public var onResult: (String) -> Void = { _ in }
    @ObservedObject var voiceSearch = VoiceSearchManager.shared
    @State private var didStart = false
    /// The task that asks for the permissions and starts the microphone.
    @State private var startTask: Task<Void, Never>?

    public init(onDismiss: @escaping () -> Void, onResult: @escaping (String) -> Void = { _ in }) {
        self.onDismiss = onDismiss
        self.onResult = onResult
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(CarTVTheme.accent.opacity(0.15))
                    .frame(width: 110, height: 110)

                Circle()
                    .fill(CarTVTheme.accent)
                    .frame(width: 76, height: 76)

                Image(systemName: "mic.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(voiceSearch.recognizedText.isEmpty ? "Listening…" : voiceSearch.recognizedText)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("Speak a channel name, movie, or category")
                .font(.system(size: 14))
                .foregroundColor(CarTVTheme.textSecondary)

            if let error = voiceSearch.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button("Done") {
                voiceSearch.stopRecording()
                onDismiss()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CarTVTheme.accent)
            .cornerRadius(12)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear { start() }
        .onDisappear {
            // The permission prompt can outlive the overlay: without this the
            // microphone opens *after* the user closed it, and the app sits
            // there recording in the background.
            startTask?.cancel()
            startTask = nil
            voiceSearch.stopRecording()
        }
    }

    /// Requests the permissions and starts listening. Without this the overlay only
    /// ever showed "Listening…" while nothing was recording.
    private func start() {
        guard !didStart else { return }
        didStart = true
        startTask = Task { @MainActor in
            guard await voiceSearch.requestPermissions() else {
                // The overlay may be gone while the prompt was up.
                guard !Task.isCancelled else { return }
                voiceSearch.errorMessage = "Voice search needs microphone and speech recognition permission."
                return
            }
            // The permission may have taken a while — the overlay may be gone.
            guard !Task.isCancelled else { return }
            do {
                try await voiceSearch.startRecording { text in
                    onResult(text)
                }
            } catch {
                // The raw system text ("com.apple.coreaudio.avfaudio error
                // 1852797029") tells the user nothing; the log keeps it.
                NSLog("DRIVEPLAY voice search: %@", error.localizedDescription)
                voiceSearch.errorMessage = "The microphone could not be opened."
            }
        }
    }
}
