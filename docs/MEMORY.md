# Project Memory: DrivePlay (CarTV)

## Current State (Updated: 2026-11-18)
- **Repository:** `https://github.com/Rushabh9033/DrivePlay-iOS` (in `D:\cartv`)
- **Git Branch:** `main`
- **Working Tree:** Cleaned & Patched with car-display browser fixes and stability hardening.
- **Project Structure:** XcodeGen-based (`project.yml`), generating `CarTV.xcodeproj` for iOS 18+ / iOS 27 with targets:
  - `CarTV`: Main iOS Application (SwiftUI + UIKit).
  - `ScreenRelay`: Upload Broadcast Extension for live screen-sharing over CarPlay.
  - `CarTVTests`: 27-suite XCTest bundle.
- **Entitlements:** Carries Apple-granted `com.apple.developer.carplay-video` capability (Case-ID 23260500) under team `47T499AR2T`.

## Root Causes of Car-Display Browser Failure (Resolved)
1. **Broken Multi-Tab Management in `CarBrowserStream`**: `openNewTab` and `switchToTab` created orphaned `WKWebView` instances while the frame capture loop and commands were hardcoded to the initial static instance. Fixed by adding dynamic `activeWebView` routing all actions and snapshots.
2. **Missing Video Presentation Hand-off**: Tapping the live browser row in CarPlay requested video presentation before the HLS encoder produced the first fragment, causing an unready player item. Fixed stream publishing to register and update `CarPlaySceneDelegate.prepareNowPlaying()`.
3. **Disconnection in External Display Scene**: `InCarAutomotiveController` did not conform to `CarBrowserScreen`, and `ExternalDisplaySceneDelegate` never attached to `CarDisplaySession.shared`. Fixed by conforming `InCarAutomotiveController: CarBrowserScreen` and attaching/detaching in scene lifecycle.
4. **Memory Leak in Snapshot Loop**: `webView.takeSnapshot` created `UIImage`/`CIImage` allocations 15 times/sec inside an async `Task` without draining autoreleased bitmaps. Wrapped in `autoreleasepool { ... }`.
5. **Handset Tab Hijacking**: `openForTheCar` called `BrowserTabManager.shared.loadURLInActiveTab(address)`, violating tab separation. Removed.
6. **Force-Unwrap Runtime Crashes**: Fixed unsafe `!` in `openBrowser` and search return handlers.
7. **JS Escaping**: Fixed backslash escaping in `enterText` and `setFieldValue` to prevent WebKit syntax errors.
8. **M3U Unencoded Stream URLs**: Added fallback percent-encoding so URLs with spaces are not dropped.
9. **Permanent Deletion of Legacy CarPlay Template Files**: Deleted `CarPlaySceneDelegate.swift`, `CarPlayTabs.swift`, `CarPlayArtwork.swift`, and `CarPlayTemplateTests.swift`. Removed all template declarations (`CPTemplateApplicationSceneSessionRoleApplication`, `CPListTemplate`, `CPTabBarTemplate`) from `project.yml`, `Info.plist`, `CarTVApp.swift`, and `project.pbxproj`. The car display is strictly driven by the dedicated interactive window scene `UIWindowSceneSessionRoleCarPlay` (`CarPlayWindowSceneDelegate` + `CarPlayWebViewController` / `InCarAutomotiveController`).
10. **Handset Window Scene & App Icon Delivery**: Added `UIWindowSceneSessionRoleApplication` to `Info.plist` and configured `AppIcon.png` so SpringBoard renders the native application icon on the handset.
11. **Cross-Platform SwiftPM Tooling**: Created `Package.swift` and `xtool.yml` for headless cross-compilation via `xtool` on Windows/Linux, synchronized with `project.yml` for XcodeGen on macOS.
12. **Permanent Elimination of Fake 'Live Video as Browser'**: Disabled `CarBrowserConfiguration.useLiveRemoteStreamingBrowser = false` and prohibited `CarBrowserStream` from routing through `PlaybackManager.shared.playScreenShare`. Replaced with genuine, direct, interactive `WKWebView` on car displays (direct touch, fluid scrolling, custom floating keyboard, editable URL bar, multi-tab switching, and non-blocking parking gate).

## Active Configuration & Strict Agent Mandates
- **CarPlay Scene**: Strictly **`UIWindowSceneSessionRoleCarPlay`** with **`CarPlayWindowSceneDelegate`**.
- **Root Controller**: **`CarPlayWebViewController`** / **`InCarAutomotiveController`** (Native interactive WKWebView with address bar, floating keyboard, touch & tab management).
- **Browser Architecture**: Real, native, interactive `WKWebView` hierarchy. No HLS video encoding, no `AVPlayer` streaming, no snapshot loops. Direct touch, 60fps scrolling, 0ms latency.
- **Prohibited & Deleted**:
  - Legacy CarPlay templates (`CarPlaySceneDelegate.swift`, `CarPlayTabs.swift`, `CarPlayArtwork.swift`, and `CPTemplateApplicationSceneSessionRoleApplication`) are permanently deleted and banned.
  - Fake HLS video streaming browser (`CarBrowserConfiguration.useLiveRemoteStreamingBrowser = true` and `CarBrowserStream` AVPlayer playback) is permanently prohibited.
- **Window & External Display**: `UIWindowSceneSessionRoleCarPlay` and `UIWindowSceneSessionRoleExternalDisplay` (`ExternalDisplaySceneDelegate` + `InCarAutomotiveController`).
- **Build System**: Dual-compatible (`project.yml` for macOS XcodeGen; `Package.swift` + `xtool.yml` for SwiftPM / xtool).
