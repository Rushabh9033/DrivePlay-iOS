import XCTest
@testable import CarTV

/// A screen capture that outlives the external display keeps the system
/// recording indicator on and drains the battery.
@MainActor
final class ScreenCaptureLifecycleTests: XCTestCase {

    /// AC14: when the external display goes away, the capture is stopped.
    /// Nothing used to ask the controller to stop — only the Cast tab's close
    /// button did, so unplugging the display left the recording running.
    func test_AC14_disconnecting_the_external_display_stops_the_screen_capture() {
        let delegate = ExternalDisplaySceneDelegate()
        let controller = InCarAutomotiveController()
        controller.isMirroringActive = true
        delegate.controller = controller

        delegate.teardown()

        XCTAssertFalse(controller.isMirroringActive, "the capture must not outlive the display")
        XCTAssertNil(delegate.controller)
        XCTAssertNil(delegate.window)
    }

    /// AC15: `stopMirroring()` is the single stop path. It clears the active
    /// flag even when the recorder reports that nothing was running — which is
    /// the case on the Simulator, where no capture can ever start.
    func test_AC15_stopping_the_mirror_clears_the_active_flag() {
        let controller = InCarAutomotiveController()
        controller.isMirroringActive = true

        controller.stopMirroring()

        XCTAssertFalse(controller.isMirroringActive)
    }
}
