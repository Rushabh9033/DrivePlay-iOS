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
    
    @Published public var headingDegrees: Double = 0.0
    @Published public var compassDirection: String = "N"
    
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
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
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
            if location.course >= 0 {
                self.headingDegrees = location.course
                self.compassDirection = Self.cardinalDirection(from: location.course)
            }
            
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
                self.headingDegrees = deg
                self.compassDirection = Self.cardinalDirection(from: deg)
            }
        }
    }
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.satelliteStatusText = "Searching for Satellites..."
        }
    }
    
    private static func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360.0) / 45.0)
        return directions[max(0, min(7, index))]
    }
}
