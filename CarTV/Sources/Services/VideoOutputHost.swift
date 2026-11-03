import AVFoundation
import UIKit

/// The video output the player draws into while the phone shows no picture.
///
/// A video-only `AVPlayerItem` never renders without an output: CoreMedia logs
/// *"video-only item is waiting for video output"*, `timeControlStatus` stays
/// `.waiting` and the playhead never leaves zero — while the stream itself is
/// perfectly fine. On the car the phone shows no player at all (the docked
/// player only exists in the `.docked` mode), so without this output the item
/// never starts and the car's display stays black.
///
/// The view lives in a window of its own: it has to outlive the docked player
/// and the phone being minimised.
final class VideoOutputHost {

    private var window: UIWindow?
    private var view: PlayerUIView?

    /// True while the player has an output of the app's own.
    var isAttached: Bool { view != nil }

    /// The phone's own scene — never the car's.
    private static func phoneScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    /// Gives the player an output. Doing it twice with the same player is a
    /// no-op, so the player can be handed over without a flicker.
    func attach(to player: AVPlayer) {
        if let view, view.playerLayer.player === player { return }
        detach()

        let view = PlayerUIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        self.view = view

        guard let scene = Self.phoneScene() else { return }
        let window = UIWindow(windowScene: scene)
        window.frame = view.bounds
        // Nearly invisible, but not hidden: a hidden window renders nothing.
        window.alpha = 0.02
        window.addSubview(view)
        // Not made key — the app's own window has to stay the key one.
        window.isHidden = false
        self.window = window
    }

    func detach() {
        view?.playerLayer.player = nil
        view?.removeFromSuperview()
        view = nil
        window?.isHidden = true
        window = nil
    }
}
