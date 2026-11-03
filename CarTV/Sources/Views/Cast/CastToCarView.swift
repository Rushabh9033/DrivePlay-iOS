import SwiftUI
import AVKit
import ReplayKit

public struct CastToCarView: View {
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Card: Car Screen Mirroring
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.08, green: 0.12, blue: 0.20), Color(red: 0.02, green: 0.04, blue: 0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("AirPlay · Screen Mirror", systemImage: "airplayvideo")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(CarTVTheme.accent)
                                Spacer()
                                Image(systemName: "car.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Text("Mirror iPhone to Car Display")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            
                            Text("Wirelessly mirror your entire iPhone screen or cast videos directly to your car head unit, external monitor, or smart display.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.75))
                                .lineSpacing(3)
                        }
                        .padding(20)
                    }
                    .padding(.horizontal, 16)
                    
                    // Option 1: Native AirPlay Video / Screen Route Picker (Entire Card Works As Button)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wireless Screen Mirroring (AirPlay)")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(CarTVTheme.textPrimary)
                        
                        ZStack {
                            HStack(spacing: 14) {
                                Image(systemName: "airplayvideo")
                                    .font(.system(size: 26))
                                    .foregroundColor(CarTVTheme.accent)
                                    .frame(width: 36)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Select AirPlay Display")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(CarTVTheme.textPrimary)
                                    Text("Tap anywhere on this card to connect to your car screen, Apple TV, or wireless display.")
                                        .font(.system(size: 12))
                                        .foregroundColor(CarTVTheme.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            
                            FullCardRoutePickerOverlay()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Option 2: Live screen share — the app captures the screen,
                    // serves it as a stream and plays it, which is what puts the
                    // phone's screen on the car's display.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share Your Screen To The Car")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(CarTVTheme.textPrimary)

                        ScreenShareCard()
                    }
                    .padding(.horizontal, 16)
                    
                    // Hardware Cable Note
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("Wired HDMI / Lightning / USB-C Direct Connection")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        Text("Connect a Lightning or USB-C to HDMI adapter directly to your car head unit for zero-latency 1080p 60fps mirror playback.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            .navigationTitle("Screen Mirroring")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Full Card AirPlay Route Picker Overlay (Direct HitTest Redirection)

public final class FullCardRoutePickerUIView: UIView, AVRoutePickerViewDelegate {
    public let pickerView = AVRoutePickerView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        pickerView.prioritizesVideoDevices = true
        pickerView.tintColor = .clear
        pickerView.isUserInteractionEnabled = true
        pickerView.delegate = self
        addSubview(pickerView)
    }

    /// The user is about to pick a route. A player that took the picture back
    /// from the car is no longer allowed to leave the phone, so it has to be
    /// allowed to again — otherwise the route is picked and nothing happens.
    public func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        PlaybackManager.shared.prepareForCar()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        pickerView.frame = bounds
        for subview in pickerView.subviews {
            if let button = subview as? UIButton {
                button.frame = bounds
                button.tintColor = .clear
            }
        }
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        for subview in pickerView.subviews {
            if let button = subview as? UIButton {
                return button
            }
        }
        return pickerView.hitTest(point, with: event) ?? pickerView
    }
}

public struct FullCardRoutePickerOverlay: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> FullCardRoutePickerUIView {
        FullCardRoutePickerUIView()
    }
    
    public func updateUIView(_ uiView: FullCardRoutePickerUIView, context: Context) {}
}

// MARK: - Broadcast picker

/// The WhatsApp-style screen share.
///
/// The app cannot start a broadcast by itself — iOS always asks the user, and
/// this picker is the control that does the asking. Only our own extension is
/// offered, so the list holds a single entry.
///
/// This is the capture that works while CarPlay is connected: the app's own
/// `RPScreenRecorder` is refused then (`RPRecordingErrorCarPlay`), a broadcast
/// is not.
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = ScreenShareService.broadcastExtensionIdentifier
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - Screen Share Card

/// The WhatsApp-style screen share: one button to start, a red banner while it
/// runs, and a Stop.
struct ScreenShareCard: View {
    @StateObject private var share = ScreenShareService.shared

    var body: some View {
        if share.state == .sharing {
            sharing
        } else if case .failed(let message) = share.state {
            failure(message)
        } else {
            startButton
        }
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The WhatsApp-style share: the user taps the button and picks the
            // relay in the system list. This is the capture that works while
            // CarPlay is connected.
            VStack(alignment: .leading, spacing: 6) {
                BroadcastPickerView()
                    .frame(height: 44)
                Text("Share this phone's screen with the car — tap the button above and choose the DrivePlay screen relay.")
                    .font(.system(size: 12))
                    .foregroundColor(CarTVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)

            Button {
                share.start()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 26))
                        .foregroundColor(CarTVTheme.accent)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(share.state == .starting ? "Starting…" : "Start sharing your screen")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(CarTVTheme.textPrimary)
                        Text("The car's screen shows this phone's screen, live.")
                            .font(.system(size: 12))
                            .foregroundColor(CarTVTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(share.state == .starting)

            // The car's row is waiting for a broadcast of the phone's screen.
            if share.isWaitingForBroadcast {
                Label(
                    "Waiting for a broadcast — choose the DrivePlay screen relay above, or start it from the Control Center.",
                    systemImage: "dot.radiowaves.left.and.right"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CarTVTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
            }

            // The CarPlay Simulator has no screen to record, so the demo feeds a
            // drawn picture through the same encoder and server.
            Button {
                share.startDemo()
            } label: {
                Label("Demo stream — no screen capture", systemImage: "play.rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CarTVTheme.accent)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(share.state == .starting)

            Text("The demo picture travels the same path as a real share, so it can be checked on the CarPlay Simulator.")
                .font(.system(size: 11))
                .foregroundColor(CarTVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            // Listen before the user picks the relay: the extension connects
            // back to the app, and it keeps trying for five minutes.
            share.startRelay()
        }
    }

    private var sharing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(share.isDemo ? "A demo picture is being shared" : "You are sharing your screen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(share.isDemo
                 ? "This device cannot record the screen, so the demo picture is being sent instead. To watch it on another screen, open this link:"
                 : "The car's screen shows this phone's screen. To watch it on another screen, open this link:")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if let url = share.networkPlaylistURL {
                Text(url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                share.stop()
            } label: {
                Text("Stop sharing")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.22))
        .cornerRadius(12)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Could not share the screen", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(CarTVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again") {
                share.start()
            }
            .font(.system(size: 14, weight: .bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
