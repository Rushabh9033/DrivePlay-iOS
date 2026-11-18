# Project Memory: DrivePlay (CarTV)

## Current State (Updated: 2026-11-18)
- **Repository:** `https://github.com/Rushabh9033/DrivePlay-iOS` (in `D:\cartv`)
- **Git Branch:** `main`
- **Working Tree:** Cleaned & Patched with simulator display fixes and dual-architecture scene routing.
- **Project Structure:** XcodeGen-based (`project.yml`), generating `CarTV.xcodeproj` for iOS 18+ / iOS 27 with targets:
  - `CarTV`: Main iOS Application (SwiftUI + UIKit).
  - `ScreenRelay`: Upload Broadcast Extension for live screen-sharing over CarPlay.
  - `CarTVTests`: 27-suite XCTest bundle.
- **Entitlements:** Carries Apple-granted `com.apple.developer.carplay-video` capability (Case-ID 23260500) under team `47T499AR2T`.

## Simulator Display & Scene Configuration Fixes (Resolved)
1. **Handset Simulator Screen Fix (`UIWindowSceneSessionRoleApplication`)**:
   - `CarTVApp.swift` previously returned `UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)` for `.windowApplication`.
   - Returning `name: nil` prevented UIKit from loading `"Default Configuration"` from `Info.plist`, breaking SwiftUI's `WindowGroup` attachment and causing the app to display a black/blank screen on the iOS simulator.
   - Fixed by returning `UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)`.
2. **CarPlay Simulator Screen Fix (`CPTemplateApplicationSceneSessionRoleApplication`)**:
   - Explicitly assigned `config.sceneClass = CPTemplateApplicationScene.self` and `config.delegateClass = CarPlaySceneDelegate.self`.
   - Guaranteed CarPlay SpringBoard discovers the application in the CarPlay grid.
   - Added duplicate connection protection in `CarPlaySceneDelegate.connect(interfaceController:window:)` to handle duplicate delegate callbacks on iOS 14+.
3. **Genuine Native Browser on Car Display (No Fake HLS Streaming)**:
   - `CarBrowserConfiguration.useLiveRemoteStreamingBrowser` is locked to `false`.
   - Browsing routes to real native `WKWebView` with direct touch interaction, smooth scrolling, and floating keyboard (`CarPlayWebViewController` / `InCarAutomotiveController`).
   - CarPlay Browser tab features clean Safari search and bookmarks without fake scroll buttons.

## Active Configuration & Strict Agent Mandates
- **CarPlay Scene**: Strictly **`UIWindowSceneSessionRoleCarPlay`** with **`CarPlayWindowSceneDelegate`**.
- **Root Controller**: **`CarPlayWebViewController`** / **`InCarAutomotiveController`** (Native interactive WKWebView with address bar, floating keyboard, touch & tab management).
- **Browser Architecture**: Real, native, interactive `WKWebView` hierarchy. No HLS video encoding, no `AVPlayer` streaming, no snapshot loops. Direct touch, 60fps scrolling, 0ms latency.
- **Prohibited & Deleted**:
  - Legacy CarPlay templates (`CarPlaySceneDelegate.swift`, `CarPlayTabs.swift`, `CarPlayArtwork.swift`, and `CPTemplateApplicationSceneSessionRoleApplication`) are permanently deleted and banned.
  - Fake HLS video streaming browser (`CarBrowserConfiguration.useLiveRemoteStreamingBrowser = true` and `CarBrowserStream` AVPlayer playback) is permanently prohibited.
- **Window & External Display**: `UIWindowSceneSessionRoleCarPlay` and `UIWindowSceneSessionRoleExternalDisplay` (`ExternalDisplaySceneDelegate` + `InCarAutomotiveController`).
- **Build System**: Dual-compatible (`project.yml` for macOS XcodeGen; `Package.swift` + `xtool.yml` for SwiftPM / xtool).
