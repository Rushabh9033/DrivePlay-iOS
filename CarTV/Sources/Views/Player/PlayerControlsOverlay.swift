import SwiftUI

public struct PlayerControlsOverlay: View {
    @ObservedObject var playbackManager = PlaybackManager.shared
    public let onBack: () -> Void
    public let onToggleFullscreen: () -> Void
    @State private var isShowingControls: Bool = true
    @State private var showTracksSheet: Bool = false
    @State private var autoHideTask: Task<Void, Never>? = nil
    
    public init(
        onBack: @escaping () -> Void,
        onToggleFullscreen: @escaping () -> Void
    ) {
        self.onBack = onBack
        self.onToggleFullscreen = onToggleFullscreen
    }
    
    // Stream is connecting, resolving, or buffering segments
    private var isBufferingOrLoading: Bool {
        if playbackManager.isBuffering { return true }
        guard let p = playbackManager.player else { return true }
        if p.timeControlStatus == .waitingToPlayAtSpecifiedRate { return true }
        if playbackManager.isPlaying && (p.rate == 0 || p.timeControlStatus != .playing) && playbackManager.currentTime <= 0.05 {
            return true
        }
        return false
    }
    
    public var body: some View {
        ZStack {
            // Tap detector to toggle overlay visibility
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingControls.toggle()
                    }
                    if isShowingControls {
                        scheduleAutoHide()
                    }
                }
            
            // Center Loading & Progress Bar (Shown while connecting or buffering)
            if isBufferingOrLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.0, green: 1.0, blue: 0.53)))
                        .scaleEffect(1.3)
                    
                    VStack(spacing: 3) {
                        Text("Loading Stream...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        
                        if let channel = playbackManager.currentChannel {
                            Text(channel.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    
                    // Animated Neon-Green Sweeping Progress Bar
                    StreamLoadingProgressBar()
                        .frame(width: 140, height: 4)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(red: 0.0, green: 1.0, blue: 0.53).opacity(0.35), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.8), radius: 16)
                .zIndex(10)
            }
            
            if isShowingControls {
                VStack {
                    // Top Bar (Clear of notch with appropriate padding)
                    HStack(spacing: 12) {
                        Button(action: onBack) {
                            Image(systemName: playbackManager.presentationMode == .fullscreen ? "chevron.left" : "xmark.circle.fill")
                                .font(.system(size: playbackManager.presentationMode == .fullscreen ? 18 : 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(6)
                        }

                        // The minimise button: the player collapses into the
                        // bar at the bottom and the video keeps playing.
                        if playbackManager.presentationMode == .docked {
                            Button(action: { playbackManager.minimizeToMiniBar() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(6)
                            }
                            .accessibilityLabel("Minimise")
                        }

                        if let channel = playbackManager.currentChannel {
                            Text(channel.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Audio & Subtitle button
                        Button(action: { showTracksSheet = true }) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, playbackManager.presentationMode == .fullscreen ? 48 : 8)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.75), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Spacer()
                    
                    // Center Play/Pause button (in Fullscreen mode)
                    if playbackManager.presentationMode == .fullscreen && !isBufferingOrLoading {
                        HStack(spacing: 36) {
                            Button(action: { playbackManager.skipBackward(seconds: 10); scheduleAutoHide() }) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: { playbackManager.togglePlayPause(); scheduleAutoHide() }) {
                                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: { playbackManager.skipForward(seconds: 10); scheduleAutoHide() }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                    } else if playbackManager.presentationMode != .fullscreen && !playbackManager.isPlaying && !isBufferingOrLoading {
                        Button(action: { playbackManager.togglePlayPause(); scheduleAutoHide() }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 6)
                        }
                        
                        Spacer()
                    }
                    
                    // Bottom Scrub Bar & Controls
                    VStack(spacing: 4) {
                        HStack(spacing: 10) {
                            // Play/Pause icon
                            Button(action: { playbackManager.togglePlayPause(); scheduleAutoHide() }) {
                                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            // Scrub bar / Live indicator
                            if playbackManager.isLiveStream || playbackManager.duration <= 0 {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("LIVE")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.red)
                                    
                                    if playbackManager.currentTime > 0 {
                                        Text("• \(formatSeconds(playbackManager.currentTime))")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    Spacer()
                                }
                            } else {
                                Slider(
                                    value: Binding(
                                        get: { playbackManager.currentTime },
                                        set: { playbackManager.seek(to: $0); scheduleAutoHide() }
                                    ),
                                    in: 0...max(playbackManager.duration, 1)
                                )
                                .tint(CarTVTheme.accent)
                                
                                Text(timeReadout)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            
                            // Fullscreen toggle icon
                            Button(action: onToggleFullscreen) {
                                Image(systemName: playbackManager.presentationMode == .fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            // The switch between the car's display and the phone. It stays
            // there while the video plays, so the picture can be moved without
            // stopping it.
            CarOutputSwitch()
                .padding(.horizontal, 12)
                .padding(.top, 44)
                .padding(.bottom, 44)
        }
        .sheet(isPresented: $showTracksSheet) {
            AudioSubtitlePickerSheet()
        }
        .onAppear {
            scheduleAutoHide()
        }
    }
    
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
            if !Task.isCancelled && playbackManager.isPlaying {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isShowingControls = false
                }
            }
        }
    }
    
    private var timeReadout: String {
        let cur = formatSeconds(playbackManager.currentTime)
        let total = formatSeconds(playbackManager.duration)
        return "\(cur) / \(total)"
    }
    
    private func formatSeconds(_ secs: Double) -> String {
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

// MARK: - Animated Stream Loading Progress Bar
private struct StreamLoadingProgressBar: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.8, blue: 0.45),
                                Color(red: 0.0, green: 1.0, blue: 0.53),
                                Color(red: 0.45, green: 1.0, blue: 0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: isAnimating ? geo.size.width * 0.55 : 0)
                    .shadow(color: Color(red: 0.0, green: 1.0, blue: 0.53).opacity(0.8), radius: 4)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }
}
