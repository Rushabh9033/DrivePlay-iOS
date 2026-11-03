import SwiftUI
import AVKit
import MediaPlayer

public struct OfflineVaultPlayerView: View {
    public let item: LocalVideoItem
    public let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    
    // UI Controls visibility
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    
    // Gesture feedback overlays
    @State private var showBrightnessHUD: Bool = false
    @State private var brightnessLevel: Double = Double(UIScreen.main.brightness)
    
    @State private var showVolumeHUD: Bool = false
    /// The player's own volume. It starts at the player's real value — the
    /// HUD used to claim 50 % while the audio was playing at 100 %.
    @State private var volumeLevel: Double = 1.0
    
    @State private var showScrubHUD: Bool = false
    @State private var scrubDeltaSeconds: Double = 0
    
    @State private var timeObserver: Any?
    
    private let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    public init(item: LocalVideoItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Video Player surface
                if let p = player {
                    if !item.isAudioOnly {
                        Color.black.edgesIgnoringSafeArea(.all)
                    } else {
                        // Audio Only Player Visualizer
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(CarTVTheme.accent.opacity(0.15))
                                    .frame(width: 140, height: 140)
                                Image(systemName: "headphones")
                                    .font(.system(size: 60))
                                    .foregroundColor(CarTVTheme.accent)
                            }
                            Text(item.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Text("OFFLINE HIGH-RES AUDIO (\(item.formatBadge))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(CarTVTheme.textSecondary)
                        }
                        
                        // Interactive Gesture Detection Surface for Audio
                        gestureSurface(size: geo.size)
                        
                        // Player Controls Overlay for Audio
                        if showControls {
                            controlsOverlay
                        }
                    }
                }
            }
        }
        .onAppear {
            if !item.isAudioOnly {
                PlaybackManager.shared.playOffline(item: item, inLandscape: true)
                onDismiss()
                return
            }
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
    }
    
    // MARK: - Gesture Detection
    
    @ViewBuilder
    private func gestureSurface(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                if location.x < size.width / 2 {
                    seekRelative(by: -10)
                } else {
                    seekRelative(by: 10)
                }
            }
            .onTapGesture(count: 1) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                if showControls { resetControlsTimer() }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        handleDragChanged(value: value, size: size)
                    }
                    .onEnded { value in
                        handleDragEnded(value: value)
                    }
            )
    }
    
    private func handleDragChanged(value: DragGesture.Value, size: CGSize) {
        let horizontal = abs(value.translation.width) > abs(value.translation.height)
        
        if horizontal {
            // Horizontal Scrubbing
            showScrubHUD = true
            let seekFactor: Double = duration > 600 ? 0.3 : 0.15
            scrubDeltaSeconds = Double(value.translation.width) * seekFactor
        } else {
            // Vertical Drag: Left side = Brightness, Right side = Volume
            let deltaY = -Double(value.translation.height) / 250.0
            if value.startLocation.x < size.width / 2 {
                // Brightness
                showBrightnessHUD = true
                let newB = max(0.0, min(1.0, Double(UIScreen.main.brightness) + deltaY * 0.05))
                UIScreen.main.brightness = CGFloat(newB)
                brightnessLevel = newB
            } else {
                // Volume
                showVolumeHUD = true
                let newV = max(0.0, min(1.0, volumeLevel + deltaY * 0.05))
                volumeLevel = newV
                player?.volume = Float(newV)
            }
        }
    }
    
    private func handleDragEnded(value: DragGesture.Value) {
        if showScrubHUD {
            seekRelative(by: scrubDeltaSeconds)
            showScrubHUD = false
            scrubDeltaSeconds = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                showBrightnessHUD = false
                showVolumeHUD = false
            }
        }
    }
    
    // MARK: - On-screen HUD Component
    
    @ViewBuilder
    private func hudIndicator(icon: String, title: String, value: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            ProgressView(value: value, total: 1.0)
                .tint(CarTVTheme.accent)
                .frame(width: 100)
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(16)
        .background(Color.black.opacity(0.75))
        .cornerRadius(14)
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 14) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.formatBadge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CarTVTheme.accent)
                            .cornerRadius(4)
                        Text("• Offline Vault • \(item.formattedSize)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Speed Selector Menu
                Menu {
                    ForEach(availableRates, id: \.self) { rate in
                        Button(action: {
                            playbackRate = rate
                            player?.rate = isPlaying ? rate : 0
                        }) {
                            HStack {
                                Text(String(format: "%.2fx", rate))
                                if playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2fx", playbackRate))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(
                LinearGradient(colors: [Color.black.opacity(0.8), Color.clear], startPoint: .top, endPoint: .bottom)
            )
            
            Spacer()
            
            // Center Play / Pause & Skip
            HStack(spacing: 40) {
                Button(action: { seekRelative(by: -10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
                
                Button(action: { seekRelative(by: 10) }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            // Bottom Scrubber Bar
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text(formatTime(currentTime))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { val in
                                currentTime = val
                                let targetTime = CMTime(seconds: val, preferredTimescale: 600)
                                player?.seek(to: targetTime)
                            }
                        ),
                        in: 0...max(duration, 1)
                    )
                    .tint(CarTVTheme.accent)
                    
                    Text(formatTime(duration))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
    
    // MARK: - Playback Logic
    
    private func setupPlayer() {
        let fileURL = LocalMediaService.shared.getFileURL(for: item)
        let playerItem = AVPlayerItem(url: fileURL)
        let p = AVPlayer(playerItem: playerItem)
        // The HUD shows the player's own volume — it used to claim 50 % while
        // the audio was playing at 100 %.
        volumeLevel = Double(p.volume)
        self.player = p
        
        // Setup background audio
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            self.currentTime = time.seconds
            if let d = p.currentItem?.duration.seconds, !d.isNaN, !d.isInfinite {
                self.duration = d
            }
        }
        
        p.play()
        p.rate = playbackRate
        isPlaying = true
        resetControlsTimer()
    }
    
    private func teardownPlayer() {
        if let token = timeObserver {
            player?.removeTimeObserver(token)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        controlsTimer?.invalidate()
    }
    
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            p.rate = playbackRate
            isPlaying = true
        }
        resetControlsTimer()
    }
    
    private func seekRelative(by seconds: Double) {
        guard let p = player else { return }
        let target = max(0, min(currentTime + seconds, duration))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        p.seek(to: time)
        resetControlsTimer()
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                if isPlaying {
                    showControls = false
                }
            }
        }
    }
    
    private func formatTime(_ secs: Double) -> String {
        guard !secs.isNaN && !secs.isInfinite && secs >= 0 else { return "00:00" }
        let total = Int(secs)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
