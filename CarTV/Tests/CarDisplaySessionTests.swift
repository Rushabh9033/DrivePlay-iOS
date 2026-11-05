import XCTest
import UIKit
@testable import CarTV

/// Covers the car's **own** screen — the one with a real browser.
///
/// CarPlay's templates cannot hold a web page (there is no web template in
/// `CarPlay.framework` at all), so the Browser tab of the template scene can
/// only ever be a remote control for the phone. The app's own car screen is
/// where a browser actually runs, and it lives in the external-display scene.
@MainActor
final class CarDisplaySessionTests: XCTestCase {

    /// A stand-in for the car's own screen.
    final class FakeCarScreen: CarBrowserScreen {
        var opened: [URL] = []
        func open(address: URL) { opened.append(address) }
    }

    /// AC159: a page the car asks for opens in the car's **own** browser.
    ///
    /// The template Browser tab is a text field and a list of links — it
    /// cannot show a page, so it used to hand every address to the phone.
    /// With the car's own screen up, the page runs **on the car**.
    func test_AC159_a_page_the_car_asks_for_opens_in_the_cars_own_browser() {
        let session = CarDisplaySession()
        let screen = FakeCarScreen()
        session.attach(screen)

        let opened = session.open(address: "https://m.youtube.com")

        XCTAssertTrue(opened, "the page did not reach the car's own browser")
        XCTAssertEqual(screen.opened.map(\.absoluteString), ["https://m.youtube.com"])
    }

    /// AC160: a page the car asks for falls back to the **phone** when the
    /// car has no screen of its own.
    ///
    /// The car screen is not always there — so the old path has to survive:
    /// the page runs on the phone and the phone's screen share carries it.
    func test_AC160_a_page_falls_back_to_the_phone_when_the_car_has_no_screen() {
        let session = CarDisplaySession()

        let opened = session.open(address: "https://m.youtube.com")

        XCTAssertFalse(opened, "the page was opened on a car screen that is not there")
    }

    /// AC161: the app asks the system for the car's own screen.
    ///
    /// The scene is the **external display** role, and the system opens it
    /// only when the app asks — so the ask is the whole mechanism. Without
    /// it the car's browser can never come up.
    func test_AC161_the_app_asks_the_system_for_the_cars_own_screen() {
        let session = CarDisplaySession()
        var asked: [UISceneSession.Role] = []
        session.activateCarScreen = { asked.append($0) }

        session.requestCarScreen()

        XCTAssertEqual(asked, [.windowExternalDisplayNonInteractive],
                       "the car's own screen was never asked for")
    }

    /// AC161: the ask **stops** once the car's own screen is there.
    ///
    /// The ask is repeated while the screen has not arrived — the system
    /// refuses it while the CarPlay session is not up yet. But once the
    /// screen is there, a further ask would open a second one over it.
    func test_AC161_the_cars_own_screen_is_not_asked_for_again_once_it_is_there() {
        let session = CarDisplaySession()
        var asked = 0
        session.activateCarScreen = { _ in asked += 1 }

        session.requestCarScreen()
        XCTAssertEqual(asked, 1, "the car's own screen was never asked for")

        // The scene delegate holds the screen; the session only keeps a weak
        // reference to it, so the test has to hold it too.
        let screen = FakeCarScreen()
        session.attach(screen)
        session.requestCarScreen()

        XCTAssertEqual(asked, 1, "the car's own screen was asked for a second time")
    }

    /// AC159: the car screen that goes away is forgotten — the app must not
    /// keep handing pages to a screen that is no longer there.
    func test_AC159_a_car_screen_that_went_away_is_forgotten() {
        let session = CarDisplaySession()
        let screen = FakeCarScreen()
        session.attach(screen)
        XCTAssertTrue(session.isConnected)

        session.detach(screen)

        XCTAssertFalse(session.isConnected, "the car screen was not forgotten")
        XCTAssertFalse(session.open(address: "https://m.youtube.com"),
                       "a page went to a screen that is gone")
    }
}
