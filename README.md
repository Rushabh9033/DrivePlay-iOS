# DrivePlay (CarTV) for iOS & Apple CarPlay

DrivePlay is a automotive media streaming, IPTV, in-car web browsing, screen mirroring, and vehicle telemetry application built natively for iOS and Apple CarPlay.

Equipped with an Apple-granted **CarPlay Video capability** (`com.apple.developer.carplay-video`), DrivePlay delivers live video surfaces, native in-car web browsing, and low-latency screen casting directly to vehicle head units.

---

## Key Features

### 1. IPTV & Media Server Aggregator
- **M3U / M3U8 Playlists:** Streaming parser for `#EXTINF` metadata, category grouping, EPG TVG tags (`tvg-id`, `tvg-name`, `tvg-logo`), and radio stream flags.
- **Xtream Codes API:** Full integration with Xtream-compatible panels for Live TV channels, VOD Movies, and multi-episode TV Series.
- **Media Servers:** Connectors for **Plex**, **Jellyfin**, and **DLNA/UPnP** local network media servers.
- **Adaptive Video Player:** Powered by `AVQueuePlayer` and `AVPlayerLayer` with picture-in-picture (PiP), multi-audio track selection, subtitle selection, and seamless automotive handoff.

### 2. Apple CarPlay Native Experience
- **CarPlay Video App Entitlement:** Displays live video playback on the car head unit display (`CPPlaybackPresentation.video`).
- **4-Tab Navigation:** Streamlined automotive tab bar (`Home`, `Favorites`, `Cast`, `Browser`).
- **Now Playing Integration:** Complete lock screen and head unit media control integration via `CPNowPlayingTemplate.shared`.
- **Dual Display Architecture:** Supports primary CarPlay head units (`CPTemplateApplicationScene`) as well as secondary external displays and instrument cluster screens (`UIWindowSceneSessionRoleExternalDisplay`).

### 3. In-Car Native Web Browser & Floating Keyboard
- **Automotive Browser:** Dedicated web browser interface (`WKWebView`) featuring automotive-scale toolbar controls: Close, Back, Tabs, Home, Address Capsule with Reload, and Settings.
- **In-App Floating Keyboard:** Custom QWERTY keyboard sliding up from the bottom of the vehicle display with quick domain pills (`youtube.com`, `google.com`, `twitch.tv`), shift, numbers, symbols, and one-tap direct navigation.

### 4. Screen Mirroring via Broadcast Relay
- **Bypasses ReplayKit CarPlay Restrictions:** Uses a system upload broadcast extension (`com.rushabh.cartvv.ScreenRelay`) to mirror the device screen even while CarPlay is actively connected.
- **Low-Latency Pipeline:** Real-time CMSampleBuffer video/audio capture -> hardware-accelerated H.264/AAC encoding via `LiveScreenWriter` -> local HTTP stream -> CarPlay video output.

### 5. Universal Offline Vault with Loopback Streaming
- **Local Media Storage:** Import and organize offline videos and audio files.
- **Loopback HTTP Streaming (`VaultFileServer`):** Bypasses the iOS sandbox limitation (`AVErrorExternalPlaybackNotSupportedForAsset` / error `-11870`) by serving offline files over a secure, authenticated local HTTP loopback server directly to CarPlay.

### 6. Satellite HUD & Vehicle Telemetry
- **Offline GPS Engine:** Direct CoreLocation GPS satellite connection calculating vehicle speed (km/h and mph), true heading compass, altitude, and fix accuracy without requiring cellular connectivity.

---

## Subsystems & Architecture

```
DrivePlay
├── CarTV/
│   ├── Sources/
│   │   ├── App/          # Scene delegates (CarPlay, ExternalDisplay, App lifecycle)
│   │   ├── Models/       # Channel, PlaylistSource, Media models
│   │   ├── Parsers/      # M3UParser, XtreamParser, DLNADIDLParser
│   │   ├── Services/     # PlaybackManager, VaultFileServer, ScreenShareService, SatelliteHUD
│   │   └── Views/        # SwiftUI handset views, CarPlayVideoViewController, Floating Keyboard
│   ├── Resources/        # Assets, Plists, CarPlay entitlements
│   └── Tests/            # Unit & Integration test suite
├── ScreenRelay/          # Upload Broadcast Extension (Screen mirroring to car)
├── Shared/               # Shared encoder and streaming primitives
└── scripts/              # Verification, automated device test runners
```

---

## Build & Setup

### Prerequisites
- macOS Sonoma / Sequoia
- Xcode 16.0+ (iOS 18.0+ SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Apple Developer Account with CarPlay Video capability

### Generation & Compilation

1. **Generate Xcode Project:**
   ```bash
   xcodegen generate
   ```

2. **Compile Check (Generic iOS Device):**
   ```bash
   xcodebuild -project CarTV.xcodeproj -scheme CarTV \
     -destination 'generic/platform=iOS' -configuration Debug \
     CARPLAY_CATEGORY=video build-for-testing
   ```

3. **Install to Physical Device:**
   ```bash
   xcodebuild -project CarTV.xcodeproj -scheme CarTV \
     -destination 'id=<YOUR_DEVICE_UDID>' -configuration Debug \
     CARPLAY_CATEGORY=video -derivedDataPath build_device build

   xcrun devicectl device install app -d <YOUR_DEVICE_UDID> \
     build_device/Build/Products/Debug-iphoneos/CarTV.app
   ```

---

## License

All rights reserved. Proprietary software developed for DrivePlay / CarTV.
