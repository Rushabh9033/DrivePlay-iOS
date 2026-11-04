import XCTest
import UIKit
@testable import CarTV

/// DrivePlay is a dark-first app: the cards, the player and the whole in-car
/// screen are dark. The phone's own appearance must not turn the app light —
/// the car screen is dark whatever the phone is set to, and the phone's side
/// has to match it.
///
/// The key lives in the app's own Info.plist, so it is read from the **running
/// app** rather than from a copy in the repository: the test proves what the
/// phone is actually running.
final class AppearanceTests: XCTestCase {

    /// AC111: the app is dark whatever the system says.
    func test_AC111_the_app_is_dark_whatever_the_system_says() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String,
                       "Dark",
                       "the app's own Info.plist has to ask for the dark appearance")
        XCTAssertEqual(UITraitCollection.current.userInterfaceStyle, .dark,
                       "the running app has to be dark")
    }
}
