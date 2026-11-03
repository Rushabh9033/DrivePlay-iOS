import XCTest
import AVFoundation
@testable import CarTV

/// The voice search and the player share one phone, so they share one audio
/// session — and the voice search has to be able to take the microphone while
/// the player holds it.
@MainActor
final class VoiceSearchTests: XCTestCase {

    /// AC67: the voice search can take the microphone from the player.
    ///
    /// The player holds the audio session as `.playback` — a category with no
    /// input route. An engine that is born on that session comes up with a
    /// 0 Hz input format and refuses to start (*"IsFormatSampleRateAnd
    /// ChannelCountValid"*, *"com.apple.coreaudio.avfaudio error
    /// 1852797029"*), which is what the voice search used to show instead of
    /// listening.
    func test_AC67_the_voice_search_can_take_the_microphone_from_the_player() async throws {
        try XCTSkipIf(AVAudioApplication.shared.recordPermission != .granted,
                      "the microphone permission is not granted on this device")

        // The microphone has to be free before the app's own path can be
        // judged: while a car is connected the phone's audio route belongs to
        // the car, and the system then refuses to open the microphone **for
        // every app** — the probe fails the same way, so the app is not the
        // reason.
        try XCTSkipUnless(canOpenTheMicrophone(),
                          "the microphone cannot be opened on this device right now — the car holds the phone's audio route")

        // The player's session.
        PlaybackManager.shared.setupAudioSession()

        let manager = VoiceSearchManager.shared
        do {
            try await manager.startRecording { _ in }
        } catch {
            let nsError = error as NSError
            XCTFail("the voice search could not take the microphone: "
                    + "\(nsError.domain) \(nsError.code) \(nsError.userInfo) — \(error.localizedDescription)")
            return
        }
        XCTAssertTrue(manager.isRecording, "the microphone was taken but nothing is recording")
        manager.stopRecording()
    }

    /// AC68: the player's session comes back when the voice search ends.
    ///
    /// The voice search borrows the session; a video that is playing has to
    /// get its sound back when the microphone is released — **and when the
    /// microphone could not be taken at all**: a car that holds the audio
    /// route must not cost the video its sound.
    func test_AC68_the_players_session_comes_back_after_the_voice_search() async throws {
        try XCTSkipIf(AVAudioApplication.shared.recordPermission != .granted,
                      "the microphone permission is not granted on this device")

        let manager = VoiceSearchManager.shared
        var recording = false
        do {
            try await manager.startRecording { _ in }
            recording = true
        } catch {
            // The microphone could not be opened — the session still has to
            // come back to the player.
            NSLog("DRIVEPLAY tests: the microphone could not be opened — %@",
                  error.localizedDescription)
        }
        if recording { manager.stopRecording() }

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "the player did not get its audio session back")
    }

    /// Opens the microphone the plain way — no app code at all.
    ///
    /// When even this fails, the device's microphone is taken by something
    /// else (a connected car owns the phone's audio route), and no app on the
    /// phone can open it. The player's session is put back before the answer
    /// is given, so the probe never costs the rest of the suite its audio.
    private func canOpenTheMicrophone() -> Bool {
        let session = AVAudioSession.sharedInstance()
        defer { PlaybackManager.shared.setupAudioSession() }
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return false }
            engine.prepare()
            try engine.start()
            engine.stop()
            return true
        } catch {
            NSLog("DRIVEPLAY tests: the microphone cannot be opened — %@",
                  error.localizedDescription)
            return false
        }
    }
}
