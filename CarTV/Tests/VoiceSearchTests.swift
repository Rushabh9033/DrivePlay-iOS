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
    func test_AC67_the_voice_search_can_take_the_microphone_from_the_player() throws {
        try XCTSkipIf(AVAudioApplication.shared.recordPermission != .granted,
                      "the microphone permission is not granted on this device")

        // The player's session.
        PlaybackManager.shared.setupAudioSession()

        let manager = VoiceSearchManager.shared
        do {
            try manager.startRecording { _ in }
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
    /// get its sound back when the microphone is released.
    func test_AC68_the_players_session_comes_back_after_the_voice_search() throws {
        try XCTSkipIf(AVAudioApplication.shared.recordPermission != .granted,
                      "the microphone permission is not granted on this device")

        let manager = VoiceSearchManager.shared
        try manager.startRecording { _ in }
        manager.stopRecording()

        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "the player did not get its audio session back")
    }
}
