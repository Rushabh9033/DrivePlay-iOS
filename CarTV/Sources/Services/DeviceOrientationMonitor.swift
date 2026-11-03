import UIKit
import Combine

/// Keeps the device's orientation notifications coming.
///
/// The notifications are only posted while the device is **generating** them.
/// Without `beginGeneratingDeviceOrientationNotifications()` the rotate
/// handler never runs and the docked player never turns into full screen.
public final class DeviceOrientationMonitor: ObservableObject {
    public static let shared = DeviceOrientationMonitor()

    /// The orientation of the device, as of the last notification.
    @Published public private(set) var orientation: UIDeviceOrientation = .unknown

    private var token: NSObjectProtocol?

    /// True when **this** monitor is the one that started the generation.
    ///
    /// The generation is a property of the device, not of a monitor: a second
    /// monitor that stops must not switch off what the first one started.
    private var ownsGeneration = false

    public init() {}

    /// Starts the notifications. Calling it twice is harmless.
    public func start() {
        guard token == nil else { return }
        if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            ownsGeneration = true
        }
        token = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.orientation = UIDevice.current.orientation
        }
        orientation = UIDevice.current.orientation
    }

    /// Stops the notifications again.
    public func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        // Only what this monitor started is stopped again.
        if ownsGeneration {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            ownsGeneration = false
        }
    }

    deinit {
        stop()
    }
}
