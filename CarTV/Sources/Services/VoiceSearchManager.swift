import Foundation
import Speech
import AVFoundation
import AVFAudio

@MainActor
public final class VoiceSearchManager: ObservableObject {
    public static let shared = VoiceSearchManager()
    
    @Published public var isRecording: Bool = false
    @Published public var recognizedText: String = ""
    @Published public var errorMessage: String?
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// The engine is built **for** the recording: its input node carries the
    /// format of the session it was born in.
    private var audioEngine: AVAudioEngine?
    /// `installTap` traps if a tap is already installed on the input node, so the
    /// manager has to know whether one is currently attached.
    private var hasInputTap = false

    public init() {}

    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Requests speech recognition *and* the microphone. Speech permission alone is
    /// not enough — capturing the audio needs the mic too, and neither was ever asked for.
    public func requestPermissions() async -> Bool {
        guard await requestAuthorization() else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    public func startRecording(onResult: @escaping (String) -> Void) throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizedText = ""
        errorMessage = nil

        // The player holds the session as `.playback` — a category with no input
        // route. The session is handed over to the microphone **first**: an
        // engine that is born on a session without an input comes up with a
        // 0 Hz input format and refuses to start ("IsFormatSampleRateAnd
        // ChannelCountValid"), which is what the voice search used to show as
        // "com.apple.coreaudio.avfaudio error 1852797029".
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
        } catch {
            NSLog("DRIVEPLAY voice search: the microphone could not be taken: %@", error.localizedDescription)
            throw error
        }

        // A fresh engine: the input node's format belongs to the session it was
        // built on.
        let engine = AVAudioEngine()
        audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceSearch", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw NSError(domain: "VoiceSearch", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "The microphone is not available."
            ])
        }
        // A tap left over from a previous run would make this call trap.
        removeInputTap()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasInputTap = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeInputTap()
            NSLog("DRIVEPLAY voice search: the recorder could not start: %@", error.localizedDescription)
            throw error
        }
        isRecording = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                onResult(result.bestTranscription.formattedString)
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
    }
    
    public func stopRecording() {
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }
        // Always detach the tap: if the engine never started, the tap is still there
        // and the next `installTap` would trap.
        removeInputTap()
        recognitionRequest?.endAudio()
        isRecording = false
        // The player gets its session back — a video that is playing has to get
        // its sound back with it.
        PlaybackManager.shared.setupAudioSession()
    }

    private func removeInputTap() {
        guard hasInputTap, let audioEngine else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }
}
