import Foundation
import CoreLocation
import Combine
import UIKit

public enum SpeedUnit: String, CaseIterable, Identifiable {
    case kmh = "km/h"
    case mph = "mph"

    public var id: String { rawValue }
}

public enum AltitudeUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case feet = "ft"

    public var id: String { rawValue }
}

@MainActor
public final class SatelliteHUDService: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = SatelliteHUDService()

    private let locationManager = CLLocationManager()

    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentSpeedMph: Double = 0.0
    @Published public var maxSpeedKmh: Double = 0.0
    @Published public var maxSpeedMph: Double = 0.0

    @Published public var altitudeMeters: Double = 0.0
    @Published public var altitudeFeet: Double = 0.0

    /// The heading the compass shows — **smoothed**.
    ///
    /// The magnetometer is noisy: the raw reading moves by a degree or two
    /// several times a second, and a rose that follows it raw jitters and
    /// reads as broken. The heading therefore moves *toward* the new value
    /// instead of jumping to it.
    @Published public private(set) var headingDegrees: Double = 0.0

    /// The compass point the heading names.
    @Published public private(set) var compassDirection: String = "N"

    /// Whether the **compass** is currently sure of the heading.
    ///
    /// A phone that is lying flat has no usable horizontal field to read a
    /// heading from — CoreLocation then reports the heading as uncertain by
    /// tens of degrees. Such a reading is not shown as a direction: the GPS's
    /// course takes over instead, and the screen says so.
    @Published public private(set) var isCompassReliable: Bool = false

    /// The rotation of the compass **rose** — and it is **continuous**.
    ///
    /// The rose turns **against** the heading: a car heading east has north on
    /// its **left**, so the rose is rotated by the *negative* heading. The
    /// rotation is never wrapped into 0..<360 — a wrapped rotation makes the
    /// rose spin the long way round (358°) every time the heading crosses
    /// north, which is what made it look broken.
    @Published public private(set) var compassRoseRotationDegrees: Double = 0.0

    /// The heading as it is shown, kept **continuous** (not wrapped).
    private var smoothedHeading: Double = 0

    /// True once a heading has been shown — the first one is taken as it is,
    /// there is nothing to smooth it from.
    private var hasSmoothedHeading = false

    /// The heading the **compass** reports — the direction the device faces.
    ///
    /// The GPS **course** is the direction of *travel*, not the direction the
    /// car faces, and while the car is slow it is mostly noise. So the
    /// compass is the heading and the course is only the fallback for a device
    /// without a compass — the last writer wins, and the noisy one must not
    /// overwrite the good one.
    private var compassHeading: Double?

    /// When the heading was last shown — the clock the filter runs on.
    private var lastHeadingTime: Date?

    @Published public var tripDistanceKm: Double = 0.0
    @Published public var tripDistanceMiles: Double = 0.0
    @Published public var tripDurationSeconds: Int = 0

    @Published public var speedUnit: SpeedUnit = .kmh
    @Published public var altitudeUnit: AltitudeUnit = .meters
    @Published public var isHUDMirrored: Bool = false

    @Published public var isSatelliteConnected: Bool = false
    @Published public var satelliteStatusText: String = "Connecting to Satellites..."

    private var lastLocation: CLLocation?
    private var tripTimer: Timer?
    private var isTripActive: Bool = false

    public override init() {
        super.init()
        setUp()
    }

    /// An instance that watches nothing.
    ///
    /// A live compass changes the heading while a test runs, so a test needs
    /// an instance that answers only what it is told.
    init(watchingSensors: Bool) {
        super.init()
        guard watchingSensors else { return }
        setUp()
    }

    private func setUp() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1.0
        locationManager.activityType = .automotiveNavigation

        // Auto-start immediately so real-time data is available everywhere without manual refresh
        start()

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    public func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        startTripTimer()
    }

    public func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        tripTimer?.invalidate()
        tripTimer = nil
        isTripActive = false
    }

    public func resetTrip() {
        tripDistanceKm = 0.0
        tripDistanceMiles = 0.0
        tripDurationSeconds = 0
        maxSpeedKmh = 0.0
        maxSpeedMph = 0.0
        lastLocation = nil
    }

    public func toggleUnit() {
        speedUnit = (speedUnit == .kmh) ? .mph : .kmh
        altitudeUnit = (altitudeUnit == .meters) ? .feet : .meters
    }

    public func toggleHUDMirror() {
        isHUDMirrored.toggle()
    }

    private func startTripTimer() {
        guard !isTripActive else { return }
        isTripActive = true
        tripTimer?.invalidate()
        tripTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.tripDurationSeconds += 1
            }
        }
    }

    public var formattedSpeed: String {
        let speed = (speedUnit == .kmh) ? currentSpeedKmh : currentSpeedMph
        return String(format: "%.0f", max(0, speed))
    }

    public var formattedAltitude: String {
        let alt = (altitudeUnit == .meters) ? altitudeMeters : altitudeFeet
        return String(format: "%.0f %@", alt, altitudeUnit.rawValue)
    }

    public var formattedTripDistance: String {
        if speedUnit == .kmh {
            return String(format: "%.1f km", tripDistanceKm)
        } else {
            return String(format: "%.1f mi", tripDistanceMiles)
        }
    }

    public var formattedTripDuration: String {
        let h = tripDurationSeconds / 3600
        let m = (tripDurationSeconds % 3600) / 60
        let s = tripDurationSeconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationManager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    self.locationManager.startUpdatingHeading()
                }
            default:
                break
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.isSatelliteConnected = true
            self.satelliteStatusText = "🛰️ Satellite GPS Active (Offline)"

            // Raw speed in m/s
            let speedMPS = location.speed
            if speedMPS >= 0 {
                let kmh = speedMPS * 3.6
                let mph = speedMPS * 2.23694
                self.currentSpeedKmh = kmh
                self.currentSpeedMph = mph
                if kmh > self.maxSpeedKmh { self.maxSpeedKmh = kmh }
                if mph > self.maxSpeedMph { self.maxSpeedMph = mph }
            } else {
                self.currentSpeedKmh = 0.0
                self.currentSpeedMph = 0.0
            }

            // Altitude
            let altM = location.altitude
            self.altitudeMeters = altM
            self.altitudeFeet = altM * 3.28084

            // Course / Heading from GPS vector
            //
            // The course is only the **fallback**: the compass says which way
            // the car faces, the course says which way it travels — and the
            // course of a car that is not moving is the GPS's noise, not a
            // direction.
            self.receiveCourse(location.course, speedMPS: location.speed)

            // Cumulative trip distance
            if let prev = self.lastLocation {
                let delta = location.distance(from: prev) // in meters
                if delta > 0 && delta < 5000 { // Ignore unrealistic jumps
                    self.tripDistanceKm += (delta / 1000.0)
                    self.tripDistanceMiles += (delta / 1609.34)
                }
            }
            self.lastLocation = location
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            let deg = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            Task { @MainActor in
                self.receiveCompassHeading(deg, accuracy: newHeading.headingAccuracy)
            }
        } else {
            // The compass does not know yet — this has to be visible, because
            // it is the moment the needle has nothing but the GPS's course to
            // follow.
            NSLog("DRIVEPLAY compass: the heading is not known yet (accuracy %.0f)", newHeading.headingAccuracy)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.satelliteStatusText = "Searching for Satellites..."
        }
    }

    /// The heading the **compass** reported.
    ///
    /// The compass says which way the car *faces* — so it is the heading the
    /// rose turns by. This is the seam the tests use: a `CLHeading` cannot
    /// be made, so the compass's own report comes in through here.
    ///
    /// - Parameters:
    ///   - degrees: the direction the device faces.
    ///   - accuracy: how far off the compass says it is, in degrees. A
    ///     reading that is out by tens of degrees is not a direction: a phone
    ///     lying flat has no usable horizontal field to read a heading from,
    ///     and a needle that follows such a reading points the wrong way.
    ///   - time: when the reading **arrived** — the clock the filter runs on.
    ///     It is the arrival and not the reading's own stamp: the magnetometer
    ///     hands its readings over in bursts, and what the user sees is when
    ///     the needle moved, not when the field was measured.
    func receiveCompassHeading(_ degrees: Double, accuracy: Double = 0, at time: Date = Date()) {
        // −1 is CoreLocation's "the compass does not know". It must not be
        // taken for a heading, and it must not switch the course off — a
        // compass that does not know leaves the course as the only direction.
        guard degrees.isFinite, degrees != -1 else { return }

        guard accuracy <= Self.maximumHeadingAccuracy else {
            // The compass is not sure of itself: it stops driving the needle
            // and the course takes over.
            isCompassReliable = false
            logHeading(degrees, accuracy: accuracy)
            return
        }

        compassHeading = degrees
        isCompassReliable = true
        apply(heading: degrees, at: time)
        logHeading(degrees, accuracy: accuracy)
    }

    /// The heading that was written to the log last — only a **turn** is
    /// worth a line, the magnetometer reports several times a second.
    private var lastLoggedHeading: Double?

    /// Writes the heading to the log, but only when it has really turned.
    ///
    /// The compass is the one thing on the screen the user cannot check
    /// against anything, so the value it shows has to be visible in the
    /// device's log when it is wrong.
    private func logHeading(_ degrees: Double, accuracy: Double) {
        if let last = lastLoggedHeading,
           abs(Self.shortestDelta(from: last, to: degrees)) < 10 {
            return
        }
        lastLoggedHeading = degrees
        NSLog("DRIVEPLAY compass: heading %.0f° (±%.0f°), rose %.0f°",
              degrees, accuracy, compassRoseRotationDegrees)
    }

    /// The heading the GPS **course** reported.
    ///
    /// The course is the direction of *travel*, not the direction the car
    /// faces, and while the car is slow it is mostly the GPS's noise. So it
    /// is used only when there is **no compass at all** — the last writer
    /// wins, and the noisy one must not be the one that writes last.
    ///
    /// It is also used only while the car is **moving**: the course of a car
    /// that is standing still is the GPS's noise, and following it sends the
    /// needle spinning while the car waits at the light.
    ///
    /// - Parameter time: when the fix **arrived** — the clock the filter runs
    ///   on, for the same reason the compass's is.
    func receiveCourse(_ course: Double, speedMPS: Double, at time: Date = Date()) {
        guard course >= 0 else { return }
        guard speedMPS < 0 || speedMPS >= Self.minimumSpeedForCourse else { return }
        // The course is the fallback for a device without a compass — and for
        // a compass that has lost its certainty.
        guard compassHeading == nil || !isCompassReliable else { return }
        apply(heading: course, at: time)
    }

    /// The speed below which the car counts as standing still — about 3.6 km/h.
    private static let minimumSpeedForCourse = 1.0

    /// How far off the compass is allowed to be and still steer the needle.
    ///
    /// CoreLocation reports the **error** of a heading in degrees. A phone
    /// that is lying flat has no usable horizontal field to read a heading
    /// from, and its error grows into the tens of degrees — a needle that
    /// follows such a reading points the wrong way, which is worse than the
    /// course. Twenty degrees is the point where a heading is still a
    /// direction and no longer a guess.
    private static let maximumHeadingAccuracy = 20.0

    /// How much of the gap a new heading closes — per **second**, not per
    /// reading.
    ///
    /// The magnetometer reports several times a second and the GPS once a
    /// second; a filter that closes a third of the gap per *reading* smooths
    /// one of them and not the other. A time constant is the same filter
    /// whatever feeds it.
    private static let smoothingTimeConstant: TimeInterval = 0.6

    /// Sets the heading the compass shows.
    ///
    /// The heading is **smoothed** — the display moves toward the new value
    /// instead of jumping to it — and the rose's rotation is **continuous**,
    /// so the rose never spins the long way round.
    private func apply(heading degrees: Double, at time: Date) {
        let target = Self.normalised(degrees)
        guard target.isFinite else { return }

        // How much of the gap this reading closes: the time that has passed
        // since the last one, against the filter's time constant.
        //
        // The clock only ever moves **forward**. A reading that arrives late
        // — a buffered one whose own stamp is older than the last reading
        // applied — must not drag the clock back, or the next reading would
        // close a gap that never happened.
        let elapsed = lastHeadingTime.map { max(0, time.timeIntervalSince($0)) } ?? 0
        lastHeadingTime = max(lastHeadingTime ?? time, time)

        // The first heading is taken as it is — there is nothing to smooth it
        // from. After that the display closes the gap in proportion to the
        // time that has passed.
        if hasSmoothedHeading {
            let delta = Self.shortestDelta(from: Self.normalised(smoothedHeading), to: target)
            let fraction = 1 - exp(-elapsed / Self.smoothingTimeConstant)
            smoothedHeading += delta * min(1, max(0, fraction))
        } else {
            smoothedHeading = target
            hasSmoothedHeading = true
        }

        headingDegrees = Self.normalised(smoothedHeading)
        compassRoseRotationDegrees = -smoothedHeading
        compassDirection = Self.cardinalDirection(from: headingDegrees)
    }

    /// An angle inside 0..<360.
    static func normalised(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// The shortest way from one angle to another — inside (−180, 180].
    ///
    /// This is what keeps the rose from spinning: from 359° to 1° is **two**
    /// degrees forward, not 358° backward.
    static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// The compass point a heading names.
    static func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalised(degrees) + 22.5) / 45.0) % directions.count
        return directions[index]
    }
}
