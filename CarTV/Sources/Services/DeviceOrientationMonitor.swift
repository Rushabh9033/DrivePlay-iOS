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

    public init() {}

    /// Starts the notifications. Calling it twice is harmless.
    public func start() {
        guard token == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
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
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    deinit {
        stop()
    }
}
