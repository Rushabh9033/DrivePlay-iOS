import Foundation
import AVKit
import MediaPlayer
import Combine
import os

/// The player's own log.
///
/// `os_log`, not `NSLog`: an `NSLog` line goes to the process's **stderr** and
/// never reaches the device's unified log, so the car's own log said nothing
/// about the picture. An `os_log` line is in the device log like any other.
let carPlaybackLog = Logger(subsystem: "com.rushabh.cartvv", category: "CarPlayback")

public enum PlayerPresentationMode: Equatable, Sendable {
    case hidden
    case mini         // The phone shows no picture of its own — a bar at the bottom does
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
    /// The tracks the picker offers, and the one that is on.
    ///
    /// They are read-only from the outside on purpose: the only way to change
    /// the selection is `selectAudioTrack(named:)` / `selectSubtitleTrack(named:)`,
    /// which tell AVFoundation about it. A picker that wrote the name itself
    /// moved a checkmark and changed nothing.
    @Published public private(set) var audioTracks: [String] = []
    @Published public private(set) var selectedAudioTrack: String = "Default"
    @Published public private(set) var subtitleTracks: [String] = ["Off"]
    @Published public private(set) var selectedSubtitleTrack: String = "Off"
    /// True while the picture is on the car's display instead of the phone's.
    ///
    /// The car's display is an AirPlay destination, so the player reports the
    /// route back: `isExternalPlaybackActive` is the system's own answer to
    /// "is the picture somewhere else". **The system is the only writer** —
    /// the flag is read-only from the outside, so the banner and the picture
    /// can never disagree.
    @Published public private(set) var isPlayingOnCar: Bool = false
    /// True while a car is connected to the app.
    ///
    /// The car's display is an AirPlay destination and **the app cannot pick
    /// that route itself** — only the system's list of displays can. What the
    /// app can do is offer the picture again as soon as the car is there.
    @Published public var isCarConnected: Bool = false

    /// True when the button has to fall back to the system's list of displays.
    ///
    /// With a car connected the picture goes there at once and the list is
    /// never shown; without a car the list is the only way to reach a display.
    public var needsRoutePicker: Bool { !isCarConnected }

    /// True while the picture is on its way to the car.
    ///
    /// The car has the picture only when the **system** says so — until then
    /// the phone keeps it, so the video is never on neither screen.
    public var isHandingOffToCar: Bool { pictureIntent == .car && !isPlayingOnCar }

    /// Which screen the picture is wanted on.
    ///
    /// The car's display is an AirPlay destination and **the app cannot pick
    /// that route** — only the system can. So the app *asks* (the intent) and
    /// the system's own answer decides where the picture really is.
    private enum PictureIntent {
        case phone
        case car
    }

    /// What the app is asking for.
    private var pictureIntent: PictureIntent = .phone

    /// The hand-off that is running.
    ///
    /// Every hand-off — and every picture taken back — gets a new number, so
    /// the ladder of an old hand-off stops at once. Without it a picture the
    /// user had taken back to the phone jumped back to the car a few seconds
    /// later, on its own.
    private var handOffGeneration = 0

    /// The mode the phone's picture had before the car took it.
    private var phonePresentationMode: PlayerPresentationMode = .docked

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
    /// The groups and options of the item that is playing.
    ///
    /// The names the picker shows are not enough to switch a track — only
    /// `select(_:in:)` tells AVFoundation to change it.
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var subtitleSelectionGroup: AVMediaSelectionGroup?
    private var audioSelectionOptions: [String: AVMediaSelectionOption] = [:]
    private var subtitleSelectionOptions: [String: AVMediaSelectionOption] = [:]
    /// The item the groups above came from.
    private var currentSelectionItem: AVPlayerItem?

    /// The artwork of the channel that is playing.
    ///
    /// The picture is drawn **once** per channel and kept. The now-playing
    /// info is refreshed while the video plays, and drawing a 512×512
    /// gradient with a symbol and three lines of text every time is what made
    /// the phone stutter — four times a second, on the main thread.
    private var nowPlayingArtwork: UIImage?
    private var nowPlayingArtworkChannelID: UUID?
    /// What the now-playing info last said, so it is not handed over again
    /// for a second that has not changed.
    private var lastNowPlayingSignature: String?
    private var lastNowPlayingSecond: Int = -1

    /// How many times the now-playing artwork was drawn.
    ///
    /// The count is what proves the picture is drawn once per channel.
    private(set) var artworkDrawCount: Int = 0

    /// How many times the picture was offered to the car.
    ///
    /// Every offer builds the player again, so the count is what proves the
    /// hand-off does not offer the same picture over and over.
    private(set) var offerCount: Int = 0

    /// The server that hands the vault's file to the player as an HTTP URL.
    ///
    /// The car's display is fed by the system's own video target — a process
    /// **outside** the app's sandbox — and a `file://` URL inside the container
    /// is invisible to it. The server lives as long as the file is played.
    private var vaultServer: VaultFileServer?

    public init() {
        setupAudioSession()
        setupRemoteCommands()
    }
    
    public func play(channel: Channel, presentation: PlayerPresentationMode = .docked) {
        // A file of the vault is **served over HTTP** and the player is given
        // that URL: the car's display is fed by the system's own video target —
        // a process that runs **outside** the app's sandbox — and it cannot open
        // a file inside the container. The item then fails with -11870
        // (`AVErrorExternalPlaybackNotSupportedForAsset`) the moment the car's
        // route takes the picture, and the video dies on the phone *and* on
        // the car. Any other channel ends the file's server.
        vaultServer?.stop()
        vaultServer = nil
        var assetURL = channel.streamURL
        if channel.streamURL.isFileURL {
            if let server = VaultFileServer(fileURL: channel.streamURL), let served = server.start() {
                vaultServer = server
                assetURL = served
            } else {
                // The car's video target cannot open a file inside the
                // container: the video would die there with -11870. Say so in
                // the device's log instead of failing silently.
                carPlaybackLog.error("the vault's file could not be served — the car cannot play it")
            }
        }
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

        // Record playlist-wise watch history. The vault's file is recorded as
        // the **file**, not as the served URL: the served URL dies with the
        // server, and a "watch again" row must not point at a port that is
        // gone.
        WatchHistoryStore.shared.recordWatch(channel)

        // Clean up previous item observers before setting new item
        cleanupObservers()

        // Fast-loading AVURLAsset with native AppleCoreMedia user-agent
        let asset: AVURLAsset
        if assetURL.isFileURL {
            asset = AVURLAsset(url: assetURL)
        } else {
            asset = AVURLAsset(
                url: assetURL,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "User-Agent": "AppleCoreMedia/1.0.0 (iPhone; iOS 18.0)",
                        "Accept": "*/*"
                    ]
                ]
            )
        }
        let playerItem = AVPlayerItem(asset: asset)
        // The tracks of the old item belong to it — the new one starts with
        // nothing to offer.
        resetMediaSelectionState()
        playerItem.preferredForwardBufferDuration = 1.0
        playerItem.automaticallyPreservesTimeOffsetFromLive = true
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        if player == nil {
            let p = AVPlayer()
            // The player's flags have to be set **before** the item is
            // attached: the system looks at the route when the item arrives,
            // and a player that forbids the picture from leaving the phone
            // keeps it local for good.
            p.allowsExternalPlayback = true
            p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            p.replaceCurrentItem(with: playerItem)
            self.player = p
        } else {
            // The same order for a player that is already there: it may have
            // been told to keep the picture on the phone.
            player?.allowsExternalPlayback = true
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

        // A car is connected, so the picture belongs to it: a video the user
        // starts on the phone goes to the car's display at once — and a video
        // the **car** asked for is offered to it again and again, because the
        // car's video endpoint may not be there yet when the row is tapped.
        //
        // The picture is **not** offered again straight away: the item was
        // attached a moment ago with the route already open, so the system
        // has looked at it. Offering it again would build the player a second
        // time — the stutter that made a start feel laggy.
        if isCarConnected {
            handOffToCar(offerImmediately: false)
        }
    }
    
    public func playOffline(item: LocalVideoItem, inLandscape: Bool = true) {
        play(channel: Channel(id: item.id,
                              name: item.title,
                              streamURL: LocalMediaService.shared.getFileURL(for: item),
                              groupTitle: "Offline Vault",
                              logoURL: nil,
                              duration: item.duration),
             presentation: inLandscape ? .fullscreen : .docked)
    }
    
    /// Plays the live screen-share stream.
    ///
    /// This is how the phone's screen reaches the car: the car screen shows the
    /// video the app plays, never a mirror of the app. The same player is offered
    /// to AirPlay receivers, so a head unit that is not CarPlay can show it too.
    public func playScreenShare(url: URL, title: String) {
        cleanupObservers()

        // The vault's file is not played any more: its server goes with it.
        vaultServer?.stop()
        vaultServer = nil

        let playerItem = AVPlayerItem(url: url)
        resetMediaSelectionState()
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

        // The share is **for the car**: the picture is offered to it, and
        // offered again while the car has not taken it. Without this the share
        // played on the phone and the car's display stayed black.
        //
        // The phone must not show the video it is capturing, so the phone's own
        // picture of the share stays hidden.
        if isCarConnected {
            phonePresentationMode = .hidden
            handOffToCar(offerImmediately: false)
        }
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

    // MARK: - The minimised player

    /// True while the phone shows the minimised player — the bar at the
    /// bottom of the screen.
    ///
    /// The bar is the phone's own player while the video is playing: the phone
    /// draws no picture of its own, so the frames go into the app's offscreen
    /// output and the car's display can still take them.
    public var showsMiniPlayer: Bool { presentationMode == .mini && currentChannel != nil }

    /// Collapses the player into the bar at the bottom.
    ///
    /// The video keeps playing — only the phone's own picture of it goes away.
    public func minimizeToMiniBar() {
        guard player != nil, currentChannel != nil else { return }
        presentationMode = .mini
    }

    /// Brings the minimised player back to the full screen.
    public func expandFromMiniBar() {
        guard presentationMode == .mini else { return }
        presentationMode = .docked
    }

    /// Plays the next channel of the group the current one belongs to.
    ///
    /// - Parameter siblings: the channels of the current channel's **own**
    ///   group, in the order they play (`PlaylistStore.channels(inGroupOf:)`).
    ///   Live television has no last channel, so the list wraps around.
    ///
    /// The player stays where it was: a next channel played from the minimised
    /// bar stays minimised.
    @discardableResult
    public func playNextChannel(in siblings: [Channel]) -> Bool {
        guard let current = currentChannel else { return false }
        guard !siblings.isEmpty,
              let index = siblings.firstIndex(where: { $0.id == current.id }) else { return false }
        let next = siblings[(index + 1) % siblings.count]
        play(channel: next, presentation: presentationMode)
        return true
    }

    // MARK: - The picture: on the phone or on the car

    /// Takes the picture back from the car's display.
    ///
    /// The route belongs to the player, so the item is replaced to leave the
    /// external display — the picture is on the phone again. The phone's own
    /// picture comes back too: it was taken away when the car took it, and
    /// nothing brought it back on its own.
    public func castToPhone() {
        guard let p = player else { return }
        // The picture is wanted on the phone: the ladder of the hand-off
        // stops here, so the picture cannot jump back to the car on its own.
        handOffGeneration += 1
        pictureIntent = .phone
        p.allowsExternalPlayback = false
        if let item = p.currentItem {
            p.replaceCurrentItem(with: item)
        }
        p.play()
        isPlaying = true
        presentationMode = phonePresentationMode
        updateNowPlayingInfo()
    }

    /// The "Play on Car Display" button.
    ///
    /// With a car connected the picture goes there at once — the system's list
    /// of displays is **never** shown. Without a car there is nowhere to go,
    /// and the list is the only way to reach a display.
    @discardableResult
    public func playOnCarDisplay() -> Bool {
        guard isCarConnected else { return false }
        handOffToCar()
        return true
    }

    /// Moves the picture to the car's display.
    ///
    /// The car owns the picture — but only **once the system says so**. Until
    /// then the phone keeps drawing it: the hand-off hid the phone's picture
    /// straight away, so a car whose video endpoint was not ready yet left
    /// the video on **neither** screen, and the user saw "sometimes only in the
    /// car, sometimes only on the phone".
    ///
    /// The stream keeps running and the output the frames go into moves with
    /// it — otherwise the item waits for a video output that never comes and
    /// the car's display stays black.
    ///
    /// - Parameter offerImmediately: the picture is offered at once. A video
    ///   that has just been started does not need it: the item was attached
    ///   with the route already open, and offering it again right away would
    ///   build the player a second time — a stutter at the start.
    public func handOffToCar(offerImmediately: Bool = true) {
        guard player != nil else { return }
        // A new hand-off: the ladder of the old one stops here.
        handOffGeneration += 1
        pictureIntent = .car
        // The frames need somewhere to go from now on: the phone's own view
        // is not drawn while the CarPlay scene is in front, so the app keeps
        // an output of its own for as long as the picture is wanted on the car.
        updateVideoOutput()
        // The picture may be allowed to leave the phone again.
        player?.allowsExternalPlayback = true
        // The mode the phone has to come back to when the picture is taken
        // back.
        if presentationMode != .hidden { phonePresentationMode = presentationMode }
        if offerImmediately {
            offerPictureToTheCar()
        }
        scheduleReoffers(generation: handOffGeneration)
    }

    /// The system's own answer to "is the picture on the car's display?".
    ///
    /// This is the **only** place the answer is acted on: the flag the UI
    /// reads and the phone's own picture both follow it, so the banner and the
    /// picture can never disagree.
    func systemSaysPictureIsOnCar(_ onCar: Bool) {
        guard onCar != isPlayingOnCar else { return }
        isPlayingOnCar = onCar
        if onCar {
            // The car has the picture: the phone stops drawing it, and the
            // output the frames go into follows — an item with no output
            // never renders and the car's display stays black.
            if presentationMode != .hidden { phonePresentationMode = presentationMode }
            presentationMode = .hidden
        } else if pictureIntent == .car {
            // The picture is not on the car any more and the app still wants
            // it there: the phone takes it back rather than leaving it on
            // neither screen.
            presentationMode = phonePresentationMode
        }
    }

    /// The gaps between the offers of the picture to the car.
    ///
    /// The first gap is long enough for the video to **start**: an offer
    /// rebuilds the player and drops the buffer, so an offer that lands on the
    /// start is the stutter the user feels as "laggy". After that the gaps
    /// grow — a car whose endpoint is not there yet is not hammered — and the
    /// last one repeats, because the endpoint can take **two minutes** to
    /// appear.
    private static let offerGaps: [TimeInterval] = [2.5, 2.5, 4, 7, 12, 20, 30]

    /// The picture is offered again and again.
    ///
    /// The car's video endpoint appears a moment **after** the scene connects
    /// and the route is only looked at when the picture is offered — so the
    /// picture is offered again and again for a while. The ladder stops at
    /// the first sign that the picture is on the car, at the first sign that
    /// the user wants it back, and when the hand-off is replaced by a newer
    /// one.
    private func scheduleReoffers(generation: Int, gapIndex: Int = 0) {
        let gaps = Self.offerGaps
        let gap = gaps[min(gapIndex, gaps.count - 1)]
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
            guard let self = self,
                  self.handOffGeneration == generation,
                  self.pictureIntent == .car,
                  self.isCarConnected,
                  !self.isPlayingOnCar else { return }
            self.offerPictureToTheCar()
            self.scheduleReoffers(generation: generation, gapIndex: gapIndex + 1)
        }
    }

    /// Offers the picture to the car's display.
    ///
    /// The AirPlay route belongs to the system, and the system only looks at
    /// it when the picture is offered: the hand-off that happened before the
    /// CarPlay video endpoint existed found no endpoint at all and the picture
    /// stayed on the phone (the system's own log said *"Local Playback = 1"*).
    /// Replacing the item is what makes the system build a new player for it
    /// and look at the route again.
    private func offerPictureToTheCar() {
        guard let p = player else { return }
        offerCount += 1
        p.allowsExternalPlayback = true
        updateNowPlayingInfo()
        if let item = p.currentItem {
            // The offer brings the picture to the car again, so the system
            // looks at the route again — and **attaching an item that is
            // already playing starts it over**: the player resets it to zero
            // while it prepares it again, and a seek that follows is thrown
            // away with it (measured on the device: the playhead jumped back
            // to 0 after every offer — the clip played again and again, and
            // the phone said "Loading Stream…" the whole time).
            //
            // So the offer brings a **new** item for the same asset, and the
            // new one starts where the old one was.
            let position = p.currentTime()
            let fresh = AVPlayerItem(asset: item.asset)
            fresh.preferredForwardBufferDuration = item.preferredForwardBufferDuration
            fresh.automaticallyPreservesTimeOffsetFromLive = item.automaticallyPreservesTimeOffsetFromLive
            fresh.canUseNetworkResourcesForLiveStreamingWhilePaused =
                item.canUseNetworkResourcesForLiveStreamingWhilePaused
            p.replaceCurrentItem(with: fresh)
            // The observers belong to the item — the new one has to be
            // watched, or the phone keeps saying "Loading Stream…".
            setupObservers(for: fresh)
            if !isLiveStream, position.isValid, position.seconds > 0 {
                // A clip that has **ended** starts again: there is nothing to
                // keep, and the car wants to see the video.
                let length = item.duration.seconds
                let ended = length.isFinite && length > 0 && position.seconds >= length - 0.05
                fresh.seek(to: ended ? .zero : position)
            }
        }
        p.play()
        isPlaying = true
        // What the system thinks of the picture: the route it picked, whether
        // the item is playing, and whether the picture is somewhere else.
        // The log is the only place these three can be read together.
        carPlaybackLog.info("""
            offer \(self.offerCount): external \(p.isExternalPlaybackActive) \
            status \(p.timeControlStatus.rawValue) \
            time \(String(format: "%.1f", p.currentTime().seconds)) \
            rate \(p.rate)
            """)
    }

    /// The user is about to pick a route, so the video is offered to the car's
    /// display again — a player that took the picture back is not allowed to
    /// leave the phone, and the route would be picked without anything
    /// happening.
    public func prepareForCar() {
        player?.allowsExternalPlayback = true
    }

    /// The car is gone — the picture cannot be on its display any more.
    ///
    /// The system says so by itself, but the app must not wait for it: the
    /// picture would stay hidden on the phone while the car is gone, and the
    /// user would be left with a black screen.
    public func carDisconnected() {
        isCarConnected = false
        // The ladder of the hand-off stops here.
        handOffGeneration += 1
        let wasOnCar = isPlayingOnCar
        pictureIntent = .phone
        systemSaysPictureIsOnCar(false)
        if wasOnCar { presentationMode = phonePresentationMode }
        // The picture is wanted on the phone again: the output the car needed
        // is not needed now.
        updateVideoOutput()
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
        // The phone draws no picture of its own in either of these modes — the
        // car owns it, or the minimised bar does. Either way the frames need
        // an output of the app's own, or the item waits for one that never
        // comes and the car's display stays black.
        //
        // The third case is the picture **on its way to the car**: the phone's
        // own view is no output then — the CarPlay scene is in front, so the
        // phone's view is not drawn — and the car's display gets nothing.
        if presentationMode == .hidden || presentationMode == .mini || pictureIntent == .car {
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
        resetMediaSelectionState()
        videoOutput.detach()
        vaultServer?.stop()
        vaultServer = nil
        player?.pause()
        player = nil
        currentChannel = nil
        // The picture is not on the car any more: the same entry point the
        // system's own answer goes through.
        systemSaysPictureIsOnCar(false)
        handOffGeneration += 1
        pictureIntent = .phone
        presentationMode = .hidden
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        nowPlayingArtwork = nil
        nowPlayingArtworkChannelID = nil
        lastNowPlayingSignature = nil
        lastNowPlayingSecond = -1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        setOrientation(.portrait)
    }
    
    // MARK: - Native Landscape Fullscreen Management
    
    public func enterLandscapeFullscreen() {
        presentationMode = .fullscreen
        setOrientation(.landscapeRight)
    }
    
    /// Leaves the fullscreen player.
    ///
    /// The fullscreen player's **dismissal** calls this — and the dismissal
    /// also happens when the **car** takes the picture. The mode must not go
    /// back to the phone's then: the phone would draw the picture again, the
    /// app's own output would be detached with it, and the car — whose
    /// picture depends on that output — would get no frames at all.
    public func exitLandscapeFullscreen() {
        if presentationMode == .fullscreen {
            presentationMode = .docked
        }
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
            // The observer is asked for the main queue, so it is on the main
            // actor — the player is the app's, and only the main actor touches it.
            MainActor.assumeIsolated {
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
                carPlaybackLog.info("the system says the picture is on the car: \(active)")
                self.systemSaysPictureIsOnCar(active)
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
                    // one nobody can act on. The error carries the stream URL,
                    // and the stream URL carries the account's token, so
                    // neither is logged as it is.
                    let failure = itm.error.map { $0 as NSError }
                    NSLog("DRIVEPLAY playback failed: %@ %ld — %@",
                          failure?.domain ?? "?", failure?.code ?? 0,
                          (itm.asset as? AVURLAsset).map { CredentialRedactor.safeForLog($0.url) } ?? "<no URL>")
                }
            }
        }
    }
    
    /// Reads the tracks the item offers.
    ///
    /// The groups belong to this item — the selection is applied to it.
    func loadMediaSelectionTracks(item: AVPlayerItem) {
        let asset = item.asset
        self.currentSelectionItem = item
        Task {
            let legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
            let audibleGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
            // Another item took over while the groups were loading — its
            // tracks are the ones on offer now, not these.
            guard self.currentSelectionItem === item else { return }
            if let group = legibleGroup {
                var subs = ["Off"]
                var subsOptions: [String: AVMediaSelectionOption] = [:]
                for option in group.options {
                    subs.append(option.displayName)
                    subsOptions[option.displayName] = option
                }
                self.subtitleSelectionGroup = group
                self.subtitleSelectionOptions = subsOptions
                self.subtitleTracks = subs
            }
            if let audioGroup = audibleGroup {
                var audios: [String] = []
                var audioOptions: [String: AVMediaSelectionOption] = [:]
                for option in audioGroup.options {
                    audios.append(option.displayName)
                    audioOptions[option.displayName] = option
                }
                self.audioSelectionGroup = audioGroup
                self.audioSelectionOptions = audioOptions
                self.audioTracks = audios.isEmpty ? ["Stereo"] : audios
            }
        }
    }

    // MARK: - The tracks the picker offers

    /// Switches the audio to the track with this display name.
    ///
    /// Moving the checkmark is not switching a track — `select(_:in:)` is the
    /// only API that tells AVFoundation to change it. When the track is not
    /// there, nothing is changed and the previous selection stands.
    public func selectAudioTrack(named name: String) {
        guard let group = audioSelectionGroup,
              let option = audioSelectionOptions[name],
              let item = currentSelectionItem else { return }
        item.select(option, in: group)
        selectedAudioTrack = name
    }

    /// Switches the subtitles to the track with this display name.
    ///
    /// "Off" is synthetic: the group is told to fall back to its default
    /// option (the "no subtitles" one), or to deselect if it has none.
    public func selectSubtitleTrack(named name: String) {
        guard let group = subtitleSelectionGroup, let item = currentSelectionItem else { return }
        if name == "Off" {
            if let defaultOption = group.defaultOption, !isNamedSubtitle(defaultOption) {
                item.select(defaultOption, in: group)
            } else {
                item.select(nil, in: group)
            }
            selectedSubtitleTrack = "Off"
            return
        }
        guard let option = subtitleSelectionOptions[name] else { return }
        item.select(option, in: group)
        selectedSubtitleTrack = name
    }

    /// True when the option is one of the real subtitle tracks we offer.
    ///
    /// The default option of a legible group is the "no subtitles" one, unless
    /// the stream marks a real subtitle as the default.
    private func isNamedSubtitle(_ option: AVMediaSelectionOption) -> Bool {
        option.displayName != "Off" && subtitleSelectionOptions[option.displayName] != nil
    }

    /// Drops the tracks of the item that was playing.
    ///
    /// The groups and their options belong to one `AVPlayerItem`, so a new
    /// item starts with nothing to offer and the default selection.
    private func resetMediaSelectionState() {
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        audioSelectionOptions = [:]
        subtitleSelectionOptions = [:]
        currentSelectionItem = nil
        audioTracks = []
        subtitleTracks = ["Off"]
        selectedAudioTrack = "Default"
        selectedSubtitleTrack = "Off"
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
    
    /// Hands the now-playing info to the system.
    ///
    /// The info is only handed over when something in it **changed**: the
    /// system counts the seconds itself once the rate is known, and the info
    /// is refreshed four times a second while a video plays.
    func updateNowPlayingInfo() {
        guard let channel = currentChannel else { return }
        let second = Int(currentTime)
        let signature = "\(channel.id.uuidString)|\(isPlaying)|\(duration)|\(isLiveStream)|\(channel.name)"
        guard signature != lastNowPlayingSignature || second != lastNowPlayingSecond else { return }
        lastNowPlayingSignature = signature
        lastNowPlayingSecond = second
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
        if let artImage = artwork(for: channel) {
            let artwork = MPMediaItemArtwork(boundsSize: artImage.size) { _ in artImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The artwork of a channel — drawn once and kept.
    ///
    /// Drawing it costs a 512×512 gradient, a symbol and three lines of text
    /// on the main thread; doing that four times a second is what made the
    /// phone stutter while a video played.
    private func artwork(for channel: Channel) -> UIImage? {
        if nowPlayingArtworkChannelID == channel.id, let image = nowPlayingArtwork {
            return image
        }
        let image = generateChannelArtwork(for: channel)
        nowPlayingArtworkChannelID = channel.id
        nowPlayingArtwork = image
        return image
    }

    private func generateChannelArtwork(for channel: Channel) -> UIImage? {
        artworkDrawCount += 1
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
