import XCTest
import AVFoundation
@testable import CarTV

/// The gravity of the video layer: a portrait video must not sit in a
/// landscape box with black bars on both sides.
final class VideoGravityTests: XCTestCase {

    /// AC118: a portrait video fills the frame, a landscape one is fitted.
    func test_AC118_a_portrait_video_fills_the_frame() {
        // A portrait video (9:16) in a landscape box (16:9): fitted, it would
        // leave a black bar on each side.
        XCTAssertEqual(VideoGravityPolicy.gravity(for: CGSize(width: 1080, height: 1920)),
                       .resizeAspectFill,
                       "a portrait video fills the frame instead of leaving bars on both sides")

        // A landscape channel (16:9) keeps its edges: a logo at the side of
        // the picture must not be cropped away.
        XCTAssertEqual(VideoGravityPolicy.gravity(for: CGSize(width: 1920, height: 1080)),
                       .resizeAspect,
                       "a landscape video is fitted into the frame")

        // A square video is no portrait video: it is fitted.
        XCTAssertEqual(VideoGravityPolicy.gravity(for: CGSize(width: 1080, height: 1080)),
                       .resizeAspect)

        // Nothing is known yet: nothing is cropped.
        XCTAssertEqual(VideoGravityPolicy.gravity(for: .zero), .resizeAspect)
    }
}
