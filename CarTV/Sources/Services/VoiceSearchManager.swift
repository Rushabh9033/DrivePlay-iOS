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
    
    public func startRecording(onResult: @escaping (String) -> Void) async throws {
        do {
            try await takeTheMicrophone(onResult: onResult)
        } catch {
            // Whatever went wrong, the player gets its session back: a video
            // that is playing must not lose its sound because the microphone
            // could not be opened.
            PlaybackManager.shared.setupAudioSession()
            throw error
        }
    }

    private func takeTheMicrophone(onResult: @escaping (String) -> Void) async throws {
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
        NSLog("DRIVEPLAY voice search: session before — %@", describe(audioSession))
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
        } catch {
            NSLog("DRIVEPLAY voice search: the microphone could not be taken: %@", error.localizedDescription)
            throw error
        }
        NSLog("DRIVEPLAY voice search: session after — %@", describe(audioSession))

        // A connected car takes the phone's audio route — and with it the
        // microphone: the route becomes the car's own audio device
        // (`CarAudio`), and a recorder that is pointed at the car dies with
        // *"PerformCommand(*ioNode, kAUStartIO)"* → *"com.apple.coreaudio
        // .avfaudio error 1852797029"*. The phone's own microphone has to be
        // asked for by name.
        try chooseThePhonesMicrophone(on: audioSession)

        // The route to the microphone comes up **after** the session is back, and
        // the two do not arrive together: `setCategory` on a session that is
        // still active tears the old route down and builds the new one in the
        // background, and `setActive(false)` returns before the session has
        // really gone. An engine that starts in that window finds no input and
        // the recorder dies with *"com.apple.coreaudio.avfaudio error
        // 1852797029"* — the same code that works the second time round, when
        // the route is already there. Wait for the route instead of guessing.
        try await waitForMicrophone(on: audioSession)

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
        NSLog("DRIVEPLAY voice search: input format %@, output format %@",
              describe(inputNode.inputFormat(forBus: 0)), describe(recordingFormat))
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
            let nsError = error as NSError
            NSLog("DRIVEPLAY voice search: the recorder could not start: %@ (domain=%@ code=%ld userInfo=%@) — session now: %@",
                  error.localizedDescription, nsError.domain, nsError.code, nsError.userInfo,
                  describe(audioSession))
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

    /// Asks for the phone's own microphone.
    ///
    /// While a car is connected the phone's audio route belongs to the car,
    /// and the car's input cannot record: the recorder is pointed at the car
    /// and dies with *"PerformCommand(*ioNode, kAUStartIO)"* → *"com.apple
    /// .coreaudio.avfaudio error 1852797029"*. The built-in microphone has to
    /// be chosen by name.
    private func chooseThePhonesMicrophone(on session: AVAudioSession) {
        let available = session.availableInputs ?? []
        NSLog("DRIVEPLAY voice search: inputs on offer: %@",
              available.map { "\($0.portType.rawValue)(\($0.channels?.count ?? 0)ch)" }
                        .joined(separator: ","))
        guard let builtIn = available.first(where: { $0.portType == .builtInMic }) else {
            NSLog("DRIVEPLAY voice search: the phone's own microphone is not on offer")
            return
        }
        do {
            try session.setPreferredInput(builtIn)
            NSLog("DRIVEPLAY voice search: the phone's microphone was chosen")
        } catch {
            NSLog("DRIVEPLAY voice search: the phone's microphone could not be chosen: %@",
                  error.localizedDescription)
        }
    }

    /// Waits until the phone's own microphone is really on the route.
    ///
    /// The route is changed in the background, so the session can be back
    /// while the input is not there yet. Starting the engine in that window is
    /// what the recorder used to do, and the recorder used to die with
    /// *"com.apple.coreaudio.avfaudio error 1852797029"*.
    private func waitForMicrophone(on session: AVAudioSession) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "VoiceSearch", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "The microphone is not available."
        ])
    }

    /// The session's state in one line. The microphone fails in ways only the
    /// session can explain: the category it ended up in, whether it still has
    /// an input, the route it took and the rate it runs at.
    private func describe(_ session: AVAudioSession) -> String {
        let inputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue)(\($0.channels?.count ?? 0)ch)" }
            .joined(separator: ",")
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue)(\($0.channels?.count ?? 0)ch)" }
            .joined(separator: ",")
        return "category=\(session.category.rawValue) mode=\(session.mode.rawValue) "
            + "rate=\(session.sampleRate) inputAvailable=\(session.isInputAvailable) "
            + "permission=\(AVAudioApplication.shared.recordPermission.rawValue) "
            + "in=[\(inputs)] out=[\(outputs)]"
    }

    private func describe(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)Hz x\(format.channelCount) (\(format.commonFormat.rawValue))"
    }
}
