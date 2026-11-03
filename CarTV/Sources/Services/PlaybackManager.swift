import Foundation
import AVKit
import MediaPlayer
import Combine

public enum PlayerPresentationMode: Equatable, Sendable {
    case hidden
    case docked       // "Browse while you watch" docked at top
    case fullscreen   // Fullscreen video
    case carMode      // Landscape car dashboard layout
}

@MainActor
public final class PlaybackManager: ObservableObject {
    public static let shared = PlaybackManager()
    
    @Published public var currentChannel: Channel?
    @Published public var player: AVPlayer?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var isBuffering: Bool = false
    @Published public var isLiveStream: Bool = false
    @Published public var presentationMode: PlayerPresentationMode = .hidden {
        didSet { updateVideoOutput() }
    }
    @Published public var audioTracks: [String] = []
    @Published public var selectedAudioTrack: String = "Default"
    @Published public var subtitleTracks: [String] = ["Off"]
    @Published public var selectedSubtitleTrack: String = "Off"
    /// True while the picture is on the car's display instead of the phone's.
    ///
    /// The car's display is an AirPlay destination, so the player reports the
    /// route back: `isExternalPlaybackActive` is the system's own answer to
    /// "is the picture somewhere else".
    @Published public var isPlayingOnCar: Bool = false

    private var timeObserverToken: Any?
    /// True while the player is showing the live screen share rather than a channel.
    private var isScreenShare = false
    private var statusObserver: NSKeyValueObservation?
    private var bufferEmptyObserver: NSKeyValueObservation?
    private var likelyToKeepUpObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var externalPlaybackObserver: NSKeyValueObservation?
    /// The output the frames are drawn into when the phone shows no picture.
    private let videoOutput = VideoOutputHost()
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupAudioSession()
        setupRemoteCommands()
    }
    
    public func play(channel: Channel, presentation: PlayerPresentationMode = .docked) {
        self.currentChannel = channel
        self.presentationMode = presentation
        self.isBuffering = true
        self.currentTime = 0
        
        let isLikelyLive = channel.streamURL.absoluteString.contains(".m3u8") ||
                           channel.groupTitle.lowercased().contains("live") ||
                           channel.groupTitle.lowercased().contains("tv") ||
                           channel.groupTitle.lowercased().contains("news")
        self.isLiveStream = isLikelyLive
        self.duration = 0
        
        if presentation == .fullscreen {
            setOrientation(.landscapeRight)
        }
        
        // Record playlist-wise watch history
        WatchHistoryStore.shared.recordWatch(channel)
        
        // Clean up previous item observers before setting new item
        cleanupObservers()
        
        // Fast-loading AVURLAsset with native AppleCoreMedia user-agent
        let asset: AVURLAsset
        if channel.streamURL.isFileURL {
            asset = AVURLAsset(url: channel.streamURL)
        } else {
            asset = AVURLAsset(
                url: channel.streamURL,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": "AppleCoreMedia/1.0.0 (iPhone; iOS 18.0)",
                        "Accept": "*/*"
                    ]
                ]
            )
        }
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 1.0
        playerItem.automaticallyPreservesTimeOffsetFromLive = true
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        if player == nil {
            let p = AVPlayer(playerItem: playerItem)
            self.player = p
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        // The car's display is an AirPlay destination, and a CarPlay video app
        // has to support AirPlay video streaming ("Rev up your CarPlay app",
        // WWDC26) — without this the picture never leaves the phone.
        player?.allowsExternalPlayback = true
        // The picture must survive the phone being minimised or locked: the car
        // keeps showing it.
        player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        setupObservers(for: playerItem)
        // The phone shows no picture in this mode, so the output the frames are
        // drawn into has to be the app's own — otherwise the item waits for a
        // video output that never comes and the car's display stays black.
        updateVideoOutput()
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    public func playOffline(item: LocalVideoItem, inLandscape: Bool = true) {
        let url = LocalMediaService.shared.getFileURL(for: item)
        let channel = Channel(
            id: item.id,
            name: item.title,
            streamURL: url,
            groupTitle: "Offline Vault",
            logoURL: nil,
            duration: item.duration
        )
        play(channel: channel, presentation: inLandscape ? .fullscreen : .docked)
    }
    
    /// Plays the live screen-share stream.
    ///
    /// This is how the phone's screen reaches the car: the car screen shows the
    /// video the app plays, never a mirror of the app. The same player is offered
    /// to AirPlay receivers, so a head unit that is not CarPlay can show it too.
    public func playScreenShare(url: URL, title: String) {
        cleanupObservers()

        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 1.0

        let player: AVPlayer
        if let existing = self.player {
            player = existing
        } else {
            player = AVPlayer()
            self.player = player
        }
        player.allowsExternalPlayback = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.replaceCurrentItem(with: playerItem)

        currentChannel = Channel(
            id: UUID(),
            name: title,
            streamURL: url,
            groupTitle: "DrivePlay",
            logoURL: nil,
            duration: 0
        )
        // `.hidden`: the phone must not show the video it is capturing, or the
        // car would receive a picture of a picture.
        presentationMode = .hidden
        isPlaying = true
        isBuffering = true
        isLiveStream = true
        currentTime = 0
        duration = 0
        isScreenShare = true

        setupObservers(for: playerItem)
        updateVideoOutput()
        player.play()
        updateNowPlayingInfo()
    }

    /// Stops the screen-share stream, if that is what is playing.
    public func stopScreenShare() {
        guard isScreenShare else { return }
        isScreenShare = false
        closePlayer()
    }

    public func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    // MARK: - The picture: on the phone or on the car

    /// Takes the picture back from the car's display.
    ///
    /// The route belongs to the player, so the item is replaced to leave the
    /// external display — the picture is on the phone again.
    public func castToPhone() {
        guard let p = player else { return }
        p.allowsExternalPlayback = false
        if let item = p.currentItem {
            p.replaceCurrentItem(with: item)
        }
        p.play()
        isPlaying = true
        isPlayingOnCar = false
        updateNowPlayingInfo()
    }

    /// Moves the picture to the car's display.
    ///
    /// The car owns the picture: the phone stops drawing it (the docked player
    /// is torn down), the stream keeps running, and the output the frames go
    /// into moves with it — otherwise the item waits for a video output that
    /// never comes and the car's display stays black.
    public func handOffToCar() {
        guard player != nil else { return }
        // The picture may be allowed to leave the phone again.
        player?.allowsExternalPlayback = true
        presentationMode = .hidden
        player?.play()
    }

    /// The user is about to pick a route, so the video is offered to the car's
    /// display again — a player that took the picture back is not allowed to
    /// leave the phone, and the route would be picked without anything
    /// happening.
    public func prepareForCar() {
        player?.allowsExternalPlayback = true
    }

    /// Keeps the picture running while the phone is minimised or locked.
    ///
    /// The car is showing the video, so the phone going into the background
    /// must not stop it.
    public func keepPlayingInTheBackground() {
        guard let p = player, currentChannel != nil else { return }
        p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        // The docked player may be gone with the screen, so the output the
        // frames are drawn into has to be there.
        updateVideoOutput()
        p.play()
    }

    /// Keeps an output for the player while the phone shows no picture.
    ///
    /// A video-only `AVPlayerItem` never renders without an output: CoreMedia
    /// logs *"video-only item is waiting for video output"*, `timeControlStatus`
    /// stays `.waiting` and the playhead never leaves zero — while the stream
    /// itself is perfectly fine. On the car the phone shows no player at all,
    /// so this is what the picture is drawn into.
    private func updateVideoOutput() {
        guard let p = player else {
            videoOutput.detach()
            return
        }
        if presentationMode == .hidden {
            videoOutput.attach(to: p)
        } else {
            videoOutput.detach()
        }
    }

    /// True while the app keeps a video output of its own for the player.
    ///
    /// The phone's own player view is an output too, so this is only true when
    /// the phone shows no picture — the car owns it.
    var hasVideoOutput: Bool { videoOutput.isAttached }
    
    public func seek(to seconds: Double) {
        guard let p = player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    public func skipForward(seconds: Double = 10) {
        guard let p = player else { return }
        if duration > 0 {
            let target = min(currentTime + seconds, duration)
            seek(to: target)
        } else if let range = p.currentItem?.seekableTimeRanges.last?.timeRangeValue {
            let endTime = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
            let target = min(currentTime + seconds, endTime)
            seek(to: target)
        } else {
            seek(to: currentTime + seconds)
        }
    }
    
    public func skipBackward(seconds: Double = 10) {
        guard let p = player else { return }
        if duration > 0 {
            let target = max(currentTime - seconds, 0)
            seek(to: target)
        } else if let range = p.currentItem?.seekableTimeRanges.first?.timeRangeValue {
            let startTime = CMTimeGetSeconds(range.start)
            let target = max(currentTime - seconds, startTime)
            seek(to: target)
        } else {
            seek(to: max(currentTime - seconds, 0))
        }
    }
    
    public func closePlayer() {
        cleanupObservers()
        videoOutput.detach()
        player?.pause()
        player = nil
        currentChannel = nil
        presentationMode = .hidden
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        setOrientation(.portrait)
    }
    
    // MARK: - Native Landscape Fullscreen Management
    
    public func enterLandscapeFullscreen() {
        presentationMode = .fullscreen
        setOrientation(.landscapeRight)
    }
    
    public func exitLandscapeFullscreen() {
        presentationMode = .docked
        setOrientation(.portrait)
    }
    
    public func setOrientation(_ orientation: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                let geometryUpdate = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)
                windowScene.requestGeometryUpdate(geometryUpdate) { _ in }
                windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            let orientationValue: Int
            switch orientation {
            case .landscapeRight: orientationValue = UIInterfaceOrientation.landscapeRight.rawValue
            case .landscapeLeft: orientationValue = UIInterfaceOrientation.landscapeLeft.rawValue
            default: orientationValue = UIInterfaceOrientation.portrait.rawValue
            }
            UIDevice.current.setValue(orientationValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
    
    private func cleanupObservers() {
        bufferEmptyObserver?.invalidate()
        bufferEmptyObserver = nil
        likelyToKeepUpObserver?.invalidate()
        likelyToKeepUpObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        externalPlaybackObserver?.invalidate()
        externalPlaybackObserver = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    private func setupObservers(for item: AVPlayerItem) {
        cleanupObservers()
        
        timeObserverToken = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            // Dismiss loader once playback is actually rendering frames
            if self.player?.timeControlStatus == .playing && (self.currentTime > 0.05 || (self.player?.rate ?? 0) > 0) {
                if self.isBuffering {
                    self.isBuffering = false
                }
                if !self.isPlaying {
                    self.isPlaying = true
                }
            }
            self.updateNowPlayingInfo()
        }
        
        bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] itm, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Flag buffering if buffer is empty
                if itm.isPlaybackBufferEmpty {
                    self.isBuffering = true
                }
            }
        }
        
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] itm, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if itm.isPlaybackLikelyToKeepUp {
                    if self.player?.timeControlStatus == .playing {
                        self.isBuffering = false
                    }
                    if self.isPlaying {
                        self.player?.play()
                    }
                }
            }
        }
        
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                NSLog("DRIVEPLAY timeControlStatus: %ld", p.timeControlStatus.rawValue)
                switch p.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                case .playing:
                    self.isBuffering = false
                    self.isPlaying = true
                case .paused:
                    self.isPlaying = false
                @unknown default:
                    break
                }
            }
        }

        // The system's own answer to "is the picture somewhere else": the car's
        // display is an AirPlay destination.
        externalPlaybackObserver = player?.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let active = p.isExternalPlaybackActive
                NSLog("DRIVEPLAY external playback active: %@", active ? "yes" : "no")
                self.isPlayingOnCar = active
            }
        }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] itm, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if itm.status == .readyToPlay {
                    // Only dismiss buffering if stream has actually started rendering
                    if self.player?.timeControlStatus == .playing && self.currentTime > 0.05 {
                        self.isBuffering = false
                    }
                    self.isPlaying = true
                    let dur = itm.duration.seconds
                    if dur.isNaN || dur.isInfinite || dur <= 0 {
                        self.isLiveStream = true
                        self.duration = 0
                    } else {
                        self.isLiveStream = false
                        self.duration = dur
                    }
                    self.loadMediaSelectionTracks(item: itm)
                    // Guarantee player begins rendering immediately upon readyToPlay
                    self.player?.play()
                } else if itm.status == .failed {
                    self.isBuffering = false
                    self.isPlaying = false
                    // Say why the picture is not there — a silent failure is the
                    // one nobody can act on.
                    NSLog("DRIVEPLAY playback failed: %@", String(describing: itm.error))
                }
            }
        }
    }
    
    private func loadMediaSelectionTracks(item: AVPlayerItem) {
        guard let asset = item.asset as? AVURLAsset else { return }
        Task {
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                var subs = ["Off"]
                for option in group.options {
                    subs.append(option.displayName)
                }
                self.subtitleTracks = subs
            }
            if let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                var audios: [String] = []
                for option in audioGroup.options {
                    audios.append(option.displayName)
                }
                self.audioTracks = audios.isEmpty ? ["Stereo"] : audios
            }
        }
    }
    
    /// The player's audio session.
    ///
    /// The category is `.playback` and **no options**: the AirPlay and the
    /// Bluetooth options are only valid with `.playAndRecord`, and the
    /// rejected options made the whole call fail — the session was never
    /// activated, so the picture never reached the car's display over the
    /// AirPlay route.
    public func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.isPlaying = true
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 10)
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 10)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let channel = currentChannel else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyArtist: channel.groupTitle.isEmpty ? "DrivePlay Live" : channel.groupTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if !isLiveStream && duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        // High-resolution automotive artwork for car display & lockscreen
        if let artImage = generateChannelArtwork(for: channel) {
            let artwork = MPMediaItemArtwork(boundsSize: artImage.size) { _ in artImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func generateChannelArtwork(for channel: Channel) -> UIImage? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Dark automotive gradient background
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0).cgColor,
                UIColor(red: 0.01, green: 0.02, blue: 0.04, alpha: 1.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: 0, y: 512), options: [])
            }
            
            // Neon Green border outline
            let borderRect = rect.insetBy(dx: 16, dy: 16)
            let path = UIBezierPath(roundedRect: borderRect, cornerRadius: 28)
            UIColor(red: 0.0, green: 1.0, blue: 0.53, alpha: 0.4).setStroke()
            path.lineWidth = 3
            path.stroke()
            
            // Channel Play/TV Icon
            let config = UIImage.SymbolConfiguration(pointSize: 110, weight: .bold)
            if let icon = UIImage(systemName: "tv.fill", withConfiguration: config) {
                let tinted = icon.withTintColor(UIColor(red: 0.0, green: 1.0, blue: 0.53, alpha: 1.0), renderingMode: .alwaysOriginal)
                let iconRect = CGRect(x: (512 - 130) / 2, y: 110, width: 130, height: 110)
                tinted.draw(in: iconRect)
            }
            
            // Channel Title Text
            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.alignment = .center
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleParagraph
            ]
            let titleRect = CGRect(x: 32, y: 270, width: 448, height: 90)
            channel.name.draw(in: titleRect, withAttributes: titleAttrs)
            
            // Group Title Badge
            let groupText = channel.groupTitle.isEmpty ? "LIVE STREAM" : channel.groupTitle.uppercased()
            let groupParagraph = NSMutableParagraphStyle()
            groupParagraph.alignment = .center
            let groupAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.0, green: 1.0, blue: 0.53, alpha: 1.0),
                .paragraphStyle: groupParagraph
            ]
            let groupRect = CGRect(x: 32, y: 375, width: 448, height: 30)
            groupText.draw(in: groupRect, withAttributes: groupAttrs)
            
            // DrivePlay Branding
            let brandParagraph = NSMutableParagraphStyle()
            brandParagraph.alignment = .center
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.6, alpha: 1.0),
                .paragraphStyle: brandParagraph
            ]
            let brandRect = CGRect(x: 32, y: 440, width: 448, height: 20)
            "DRIVEPLAY AUTOMOTIVE CINEMA".draw(in: brandRect, withAttributes: brandAttrs)
        }
    }
}
