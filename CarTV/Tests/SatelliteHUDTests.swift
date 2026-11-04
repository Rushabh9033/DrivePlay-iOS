import XCTest
@testable import CarTV

/// The compass of the Cockpit and of the phone's cluster.
///
/// The rose turns **against** the heading and the needle stays **fixed**: a
/// car heading east has north on its **left**, so a rose that turns with the
/// heading points the opposite way — and a needle inside the rose turns with
/// it and always says north.
///
/// The heading is **smoothed** and the rose's rotation is **continuous**: a
/// rose whose rotation is wrapped into 0..<360 spins the long way round every
/// time the heading crosses north, and a rose that follows the magnetometer
/// raw jitters and reads as broken.
///
/// The smoothing runs on a **clock**, not on the number of readings: the
/// magnetometer delivers several times a second and the GPS once a second,
/// and a filter that closes a third of the gap per *reading* smooths one of
/// them and not the other.
@MainActor
final class SatelliteHUDTests: XCTestCase {

    /// A fixed moment, so a test can say *when* a reading was taken.
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// AC135: the rose turns against the heading, and the heading is
    /// normalised — a rose that ends up on the wrong side of the dial shows
    /// the wrong direction.
    func test_AC135_the_compass_rose_turns_against_the_heading() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(90)          // the car faces east
        XCTAssertEqual(hud.headingDegrees, 90)
        XCTAssertEqual(hud.compassRoseRotationDegrees, -90,
                       "a car facing east has north on its left, so the rose turns against the heading")

        // A negative heading is normalised into 0..<360 — on its own, so the
        // smoothing of the second reading does not blur the normalisation.
        let west = SatelliteHUDService(watchingSensors: false)
        west.receiveCompassHeading(-90)
        XCTAssertEqual(west.headingDegrees, 270,
                       "the heading was not normalised into 0..<360")
        XCTAssertEqual(west.compassRoseRotationDegrees, -270)
    }

    /// AC136: the compass wins over the GPS course.
    ///
    /// The course is the direction of *travel* — while the car is slow it is
    /// the GPS's noise, not a direction — and it used to overwrite the
    /// compass on every fix.
    func test_AC136_the_compass_wins_over_the_gps_course() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(120)
        hud.receiveCourse(45, speedMPS: 5)     // the GPS says the car travels north-east

        XCTAssertEqual(hud.headingDegrees, 120,
                       "the course of a slow car is noise and must not overwrite the compass")
    }

    /// AC137: the course is the fallback — it is used when there is no
    /// compass at all, and a course the GPS does not know is never used.
    func test_AC137_the_course_is_the_fallback_when_there_is_no_compass() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCourse(45, speedMPS: 5)
        XCTAssertEqual(hud.headingDegrees, 45,
                       "a device without a compass has nothing but the course")

        let other = SatelliteHUDService(watchingSensors: false)
        other.receiveCourse(-1, speedMPS: 5)   // -1 means "the GPS does not know"
        XCTAssertEqual(other.headingDegrees, 0)
    }

    /// AC138: the cardinal direction survives a negative heading.
    func test_AC138_the_cardinal_direction_survives_a_negative_heading() {
        XCTAssertEqual(SatelliteHUDService.cardinalDirection(from: 0), "N")
        XCTAssertEqual(SatelliteHUDService.cardinalDirection(from: 90), "E")
        XCTAssertEqual(SatelliteHUDService.cardinalDirection(from: 180), "S")
        XCTAssertEqual(SatelliteHUDService.cardinalDirection(from: -90), "W",
                       "a negative heading named the wrong direction")
        XCTAssertEqual(SatelliteHUDService.cardinalDirection(from: -180), "S")
    }

    /// AC143: the heading is smoothed.
    ///
    /// The magnetometer's reading moves by a degree or two several times a
    /// second; a rose that follows it raw jitters and reads as broken. The
    /// display therefore moves *toward* the new heading.
    func test_AC143_the_heading_moves_toward_the_new_value_instead_of_jumping_to_it() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(90, at: start)
        hud.receiveCompassHeading(100, at: start.addingTimeInterval(1.0))

        XCTAssertLessThan(hud.headingDegrees, 100,
                          "the display jumped to the new heading instead of moving toward it")
        XCTAssertGreaterThan(hud.headingDegrees, 90,
                             "the display did not move at all")
    }

    /// AC144: the rose does not spin when the heading crosses north.
    ///
    /// The rotation is continuous, so from 359° to 1° the rose turns two
    /// degrees forward — a wrapped rotation makes it spin 358° the long way
    /// round, which is what made the compass look broken.
    func test_AC144_the_rose_does_not_spin_when_the_heading_crosses_north() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(359, at: start)
        let before = hud.compassRoseRotationDegrees

        hud.receiveCompassHeading(1, at: start.addingTimeInterval(1.0))
        let after = hud.compassRoseRotationDegrees

        XCTAssertLessThan(abs(after - before), 5,
                          "the rose spun the long way round when the heading crossed north")
    }

    /// AC145: a compass that does not know is refused.
    ///
    /// −1 is CoreLocation's "the compass does not know". It must not be taken
    /// for a heading, and it must not switch the course off — a compass that
    /// does not know leaves the course as the only direction there is.
    func test_AC145_an_unknown_compass_heading_is_refused() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(-1)
        XCTAssertEqual(hud.headingDegrees, 0, "an unknown heading was taken for a heading")

        hud.receiveCourse(45, speedMPS: 5)
        XCTAssertEqual(hud.headingDegrees, 45,
                       "a compass that does not know must not kill the course fallback")
    }

    /// AC146: the course is only used while the car is moving.
    ///
    /// The course of a car that is standing still is the GPS's noise, and
    /// following it sends the needle spinning while the car waits at the
    /// light.
    func test_AC146_the_course_is_only_used_while_the_car_is_moving() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCourse(45, speedMPS: 0)
        XCTAssertEqual(hud.headingDegrees, 0,
                       "the course of a car that is not moving is noise, not a direction")

        hud.receiveCourse(45, speedMPS: 5)
        XCTAssertEqual(hud.headingDegrees, 45,
                       "the course of a moving car is the only direction a device without a compass has")
    }

    /// AC147: a compass that is not sure of itself does not steer the needle.
    ///
    /// CoreLocation reports the **error** of a heading in degrees. A phone
    /// lying flat has no usable horizontal field to read a heading from, and
    /// its error grows into the tens of degrees — measured on the phone:
    /// *"accuracy 27.58"*. A needle that follows such a reading points the
    /// wrong way, which is worse than the GPS's course.
    func test_AC147_a_compass_that_is_not_sure_does_not_steer_the_needle() {
        let hud = SatelliteHUDService(watchingSensors: false)

        hud.receiveCompassHeading(45, accuracy: 30)
        XCTAssertEqual(hud.headingDegrees, 0,
                       "a heading the compass is out by thirty degrees was shown as a direction")

        hud.receiveCourse(120, speedMPS: 5)
        XCTAssertEqual(hud.headingDegrees, 120,
                       "the course must take over from a compass that does not know")
    }

    /// AC148: the heading is smoothed by **time**, not by the number of
    /// readings.
    ///
    /// The magnetometer's readings arrive in bursts — measured on the phone:
    /// two readings measured a second apart were delivered 128 ms apart. A
    /// filter that closes a fixed share of the gap per *reading* moves the
    /// needle a long way in that burst, which is the jolt the user sees. A
    /// filter that runs on a clock moves it by how much **time** has passed,
    /// so the same readings move the needle less when they arrive together.
    func test_AC148_the_heading_is_smoothed_by_time_and_not_by_the_number_of_readings() {
        let burst = SatelliteHUDService(watchingSensors: false)
        burst.receiveCompassHeading(0, at: start)
        burst.receiveCompassHeading(90, at: start.addingTimeInterval(0.1))

        let spread = SatelliteHUDService(watchingSensors: false)
        spread.receiveCompassHeading(0, at: start)
        spread.receiveCompassHeading(90, at: start.addingTimeInterval(2.0))

        XCTAssertLessThan(burst.headingDegrees, 45,
                          "a burst of readings moved the needle as far as a reading spread over two seconds")
        XCTAssertGreaterThan(spread.headingDegrees, burst.headingDegrees,
                             "the same readings spread out did not move the needle further")

        // A reading that arrives **late** — a buffered one whose own stamp is
        // older than the reading already applied — must not move the needle,
        // and must not drag the filter's clock back with it: the next reading
        // would then close a gap that never happened.
        let late = SatelliteHUDService(watchingSensors: false)
        late.receiveCompassHeading(0, at: start)
        late.receiveCompassHeading(90, at: start.addingTimeInterval(2.0))
        let beforeLate = late.headingDegrees
        late.receiveCompassHeading(0, at: start.addingTimeInterval(1.0))
        XCTAssertEqual(late.headingDegrees, beforeLate, accuracy: 0.0001,
                       "a late reading moved the needle")

        let clock = SatelliteHUDService(watchingSensors: false)
        clock.receiveCompassHeading(0, at: start)
        clock.receiveCompassHeading(0, at: start.addingTimeInterval(2.0))
        clock.receiveCompassHeading(0, at: start.addingTimeInterval(1.0))   // late
        clock.receiveCompassHeading(90, at: start.addingTimeInterval(3.0))
        XCTAssertLessThan(clock.headingDegrees, 80,
                          "the filter's clock was dragged back by a late reading")
    }

    /// AC149: the compass says whether it is sure of the heading.
    ///
    /// The screen shows the compass's answer or the GPS's course, and the
    /// user has to be able to tell which one they are looking at.
    func test_AC149_the_compass_says_whether_it_is_sure_of_the_heading() {
        let hud = SatelliteHUDService(watchingSensors: false)

        XCTAssertFalse(hud.isCompassReliable, "a compass that has not spoken is not sure")

        hud.receiveCompassHeading(45, accuracy: 5, at: start)
        XCTAssertTrue(hud.isCompassReliable, "a compass that is sure did not say so")

        hud.receiveCompassHeading(46, accuracy: 30, at: start.addingTimeInterval(1.0))
        XCTAssertFalse(hud.isCompassReliable, "a compass that lost its certainty did not say so")
    }
}
