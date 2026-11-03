import SwiftUI
import AVKit

/// The switch between the car's display and the phone.
///
/// The car's display is an AirPlay destination — a CarPlay video app has to
/// support AirPlay video streaming ("Rev up your CarPlay app", WWDC26) — so
/// the picture travels the AirPlay route: the user picks the car in the
/// system's device list and the player reports the route back
/// (`isExternalPlaybackActive`). "Play on Phone" takes the picture back.
public struct CarOutputSwitch: View {
    @ObservedObject private var playback = PlaybackManager.shared

    public init() {}

    public var body: some View {
        // The banner sits at the top, the pill at the bottom — the same
        // places the reference apps put them.
        VStack(spacing: 0) {
            if playback.isPlayingOnCar {
                connected
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                pill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Play on Car Display".
    ///
    /// With a car connected the picture goes there at once — the system's list
    /// of displays is never shown. Without a car there is nowhere to go, and
    /// that list is the only way to reach a display.
    private var pill: some View {
        Group {
            if playback.needsRoutePicker {
                pillLabel.overlay { FullCardRoutePickerOverlay() }
            } else {
                Button {
                    playback.playOnCarDisplay()
                } label: {
                    pillLabel
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pillLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
            Image(systemName: "tv.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Play on Car Display")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(CarTVTheme.accent.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6)
    }

    /// "Car connected" — the picture is on the car's display.
    private var connected: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Car connected")
                .font(.system(size: 12, weight: .bold))
            Spacer(minLength: 6)
            Button {
                playback.castToPhone()
            } label: {
                Text("Play on Phone")
                    .font(.system(size: 12, weight: .bold))
            }
            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CarTVTheme.accent.opacity(0.25), in: Capsule())
        .overlay(Capsule().stroke(CarTVTheme.accent, lineWidth: 1))
    }
}
