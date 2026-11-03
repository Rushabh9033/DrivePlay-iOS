import SwiftUI
import AVKit

// MARK: - Direct Metal/CoreAnimation AVPlayerLayer Surface (Docked & In-App Views)
public final class PlayerUIView: UIView {
    public override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    public var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

public struct VideoPlayerView: UIViewRepresentable {
    public let player: AVPlayer
    public var showsPlaybackControls: Bool
    public var videoGravity: AVLayerVideoGravity
    public var onDismiss: (() -> Void)?
    
    public init(
        player: AVPlayer,
        showsPlaybackControls: Bool = false,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        onDismiss: (() -> Void)? = nil
    ) {
        self.player = player
        self.showsPlaybackControls = showsPlaybackControls
        self.videoGravity = videoGravity
        self.onDismiss = onDismiss
    }
    
    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }
    
    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
    }
}

// MARK: - Native Landscape AVPlayerViewController (Fullscreen Only)
public final class LandscapeAVPlayerViewController: AVPlayerViewController {
    public var onDismiss: (() -> Void)?
    private var skipFeedbackView: UIView?
    private var skipBackBtn: UIButton?
    private var skipForwardBtn: UIButton?
    private var autoHideTimer: Timer?
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.landscapeLeft, .landscapeRight]
    }
    
    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    public override var shouldAutorotate: Bool {
        return true
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupDoubleTapGesture()
        setupOnScreenSkipButtons()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleControlsFade()
    }
    
    private func setupDoubleTapGesture() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delaysTouchesEnded = false
        view.addGestureRecognizer(doubleTap)
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delaysTouchesEnded = false
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }
    
    private func setupOnScreenSkipButtons() {
        guard let overlay = contentOverlayView else { return }
        
        // 10s Backward Button
        let backBtn = UIButton(type: .system)
        let backConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        backBtn.setImage(UIImage(systemName: "gobackward.10", withConfiguration: backConfig), for: .normal)
        backBtn.tintColor = .white
        backBtn.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        backBtn.layer.cornerRadius = 24
        backBtn.clipsToBounds = true
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.addTarget(self, action: #selector(handleSkipBack), for: .touchUpInside)
        // Start hidden. The toggle reads the current alpha to decide whether to
        // show or hide, so a button left visible would make the first tap hide it.
        backBtn.alpha = 0

        // 10s Forward Button
        let fwdBtn = UIButton(type: .system)
        let fwdConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        fwdBtn.setImage(UIImage(systemName: "goforward.10", withConfiguration: fwdConfig), for: .normal)
        fwdBtn.tintColor = .white
        fwdBtn.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        fwdBtn.layer.cornerRadius = 24
        fwdBtn.clipsToBounds = true
        fwdBtn.translatesAutoresizingMaskIntoConstraints = false
        fwdBtn.addTarget(self, action: #selector(handleSkipForward), for: .touchUpInside)
        fwdBtn.alpha = 0

        overlay.addSubview(backBtn)
        overlay.addSubview(fwdBtn)
        
        NSLayoutConstraint.activate([
            backBtn.widthAnchor.constraint(equalToConstant: 48),
            backBtn.heightAnchor.constraint(equalToConstant: 48),
            backBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            backBtn.centerXAnchor.constraint(equalTo: overlay.centerXAnchor, constant: -95),
            
            fwdBtn.widthAnchor.constraint(equalToConstant: 48),
            fwdBtn.heightAnchor.constraint(equalToConstant: 48),
            fwdBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            fwdBtn.centerXAnchor.constraint(equalTo: overlay.centerXAnchor, constant: 95)
        ])
        
        self.skipBackBtn = backBtn
        self.skipForwardBtn = fwdBtn
    }
    
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        toggleSkipButtonsVisibility()
    }
    
    private func toggleSkipButtonsVisibility() {
        guard let back = skipBackBtn, let fwd = skipForwardBtn else { return }
        let shouldShow = back.alpha < 0.5
        
        UIView.animate(withDuration: 0.25) {
            back.alpha = shouldShow ? 1 : 0
            fwd.alpha = shouldShow ? 1 : 0
        }
        
        if shouldShow {
            scheduleControlsFade()
        } else {
            autoHideTimer?.invalidate()
        }
    }
    
    private func scheduleControlsFade() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) {
                self?.skipBackBtn?.alpha = 0
                self?.skipForwardBtn?.alpha = 0
            }
        }
    }
    
    @objc private func handleSkipBack() {
        PlaybackManager.shared.skipBackward(seconds: 10)
        showSkipFeedback(isForward: false)
        scheduleControlsFade()
    }
    
    @objc private func handleSkipForward() {
        PlaybackManager.shared.skipForward(seconds: 10)
        showSkipFeedback(isForward: true)
        scheduleControlsFade()
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let isForward = location.x > view.bounds.width / 2
        
        if isForward {
            handleSkipForward()
        } else {
            handleSkipBack()
        }
    }
    
    private func showSkipFeedback(isForward: Bool) {
        skipFeedbackView?.removeFromSuperview()
        
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        container.layer.cornerRadius = 24
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        let iconName = isForward ? "goforward.10" : "gobackward.10"
        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26)
        ])
        
        let label = UILabel()
        label.text = isForward ? "+10s" : "-10s"
        label.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        label.textColor = .white
        
        if isForward {
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(iconView)
        } else {
            stack.addArrangedSubview(iconView)
            stack.addArrangedSubview(label)
        }
        
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        
        let targetView = contentOverlayView ?? view!
        targetView.addSubview(container)
        
        let xOffset = isForward ? targetView.bounds.width * 0.25 : -targetView.bounds.width * 0.25
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: targetView.centerXAnchor, constant: xOffset),
            container.centerYAnchor.constraint(equalTo: targetView.centerYAnchor)
        ])
        
        container.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        container.alpha = 0
        
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut, animations: {
            container.transform = .identity
            container.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0.45, options: .curveEaseIn, animations: {
                container.alpha = 0
                container.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }) { _ in
                container.removeFromSuperview()
            }
        }
        
        self.skipFeedbackView = container
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || presentingViewController == nil {
            self.player = nil
            onDismiss?()
            PlaybackManager.shared.player?.play()
        }
    }
}

// MARK: - Native FullScreen Player Presenter
@MainActor
public final class NativeFullScreenPlayerPresenter: NSObject, AVPlayerViewControllerDelegate {
    public static let shared = NativeFullScreenPlayerPresenter()
    
    private var presentedPlayerVC: LandscapeAVPlayerViewController?
    private var isPresenting: Bool = false
    private var dismissHandler: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func present(player: AVPlayer, onDismiss: @escaping () -> Void) {
        guard !isPresenting else { return }
        
        // If already presenting with the exact same player, keep playing
        if let currentVC = presentedPlayerVC, currentVC.player === player {
            return
        }
        
        guard let topVC = getTopViewController() else { return }
        
        // If topVC is already a LandscapeAVPlayerViewController, simply update player
        if let existing = topVC as? LandscapeAVPlayerViewController {
            existing.player = player
            return
        }
        
        self.isPresenting = true
        self.dismissHandler = onDismiss
        
        let playerVC = LandscapeAVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.updatesNowPlayingInfoCenter = true
        playerVC.videoGravity = .resizeAspect
        playerVC.modalPresentationStyle = .fullScreen
        playerVC.delegate = self
        
        playerVC.onDismiss = { [weak self] in
            guard let self = self else { return }
            self.presentedPlayerVC = nil
            self.isPresenting = false
            let handler = self.dismissHandler
            self.dismissHandler = nil
            handler?()
            PlaybackManager.shared.player?.play()
        }
        
        self.presentedPlayerVC = playerVC
        
        PlaybackManager.shared.setOrientation(.landscapeRight)
        
        topVC.present(playerVC, animated: true) { [weak self] in
            self?.isPresenting = false
        }
    }
    
    public func dismiss() {
        guard let vc = presentedPlayerVC else { return }
        vc.player = nil
        vc.dismiss(animated: true) { [weak self] in
            self?.presentedPlayerVC = nil
            self?.isPresenting = false
            let handler = self?.dismissHandler
            self?.dismissHandler = nil
            handler?()
            PlaybackManager.shared.player?.play()
        }
    }
    
    // AVPlayerViewControllerDelegate
    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    private func getTopViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC: UIViewController?
        if let base = base {
            baseVC = base
        } else {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            let window = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
            baseVC = window?.rootViewController
        }
        
        guard let root = baseVC else { return nil }
        
        if let nav = root as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
        }
        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return getTopViewController(base: presented)
        }
        return root
    }
}
