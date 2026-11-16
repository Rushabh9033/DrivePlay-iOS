# DrivePlay iOS — Real CarPlay WebKit Browser Implementation Report

**Date:** 2026-11-16  
**Target Platform:** iOS 27 (iPhone 13 Physical Device `00008110-001C60423CB8401E`)  
**Workspace:** `/Users/radhikamac/carTv-iptv copy`  
**Reference Architecture:** Cafari Lite (`https://github.com/rPlayAI/cafari-lite`)  
**Status:** IMPLEMENTED, COMPILED, VERIFIED & PASSING ON HARDWARE

---

## 1. Executive Summary & Architecture Truth

### The Native CarPlay Constraint (`CPTemplateApplicationScene`)
In official, public Apple CarPlay guidelines and APIs, native CarPlay applications declare `CPTemplateApplicationSceneSessionRoleApplication` and connect to `CPTemplateApplicationScene`. The window provided by this scene is a `CPWindow`, rendered by an out-of-process system compositor (`CarPlayTemplateUIHost`).
- `CPWindow` **only permits CarPlay templates** (`CPListTemplate`, `CPTabBarTemplate`, `CPNowPlayingTemplate`, `CPSearchTemplate`, etc.).
- Invoking `CPWindow.rootViewController = UIViewController` or `CPWindow.addSubview(UIView)` is completely ignored or rejected by the CarPlay compositor.
- Therefore, within a standard `CPTemplateApplicationScene`, an arbitrary `WKWebView` cannot be rendered. Previous iterations displayed artificial website directories or simulated list shortcuts that could not browse live websites.

### The Real WebKit Architecture (`UIWindowSceneSessionRoleCarPlay`)
The reference implementation from **Cafari Lite** demonstrates how a real WebKit browser can draw directly on the car's head unit:
- It declares a `UIWindowScene` under the role `UIWindowSceneSessionRoleCarPlay` in the `UIApplicationSceneManifest`.
- Unlike `CPTemplateApplicationScene`, `UIWindowSceneSessionRoleCarPlay` allocates a standard `UIWindowScene` on the head-unit display.
- This permits attaching a regular UIKit `UIWindow`, setting a custom `UIViewController`, and embedding a real `WKWebView`.
- Direct user touches, tap-to-navigate, scrolling, JavaScript execution, HTML5 video playback, and CSS styling are handled by Apple's standard WebKit engine directly on the car display.

---

## 2. Cafari Lite Deep Dive & Comparative Analysis

Thorough inspection of `rPlayAI/cafari-lite` reveals the technical machinery:

| Feature / Aspect | Cafari Lite Reference | DrivePlay Implementation |
|---|---|---|
| **Scene Session Role** | `UIWindowSceneSessionRoleCarPlay` | `UIWindowSceneSessionRoleCarPlay` (coexists with `CPTemplateApplicationScene`) |
| **Scene Class** | `UIWindowScene` | `UIWindowScene` |
| **Scene Delegate** | `CarPlaySceneDelegate: UIWindowSceneDelegate` | `CarPlayWindowSceneDelegate: UIWindowSceneDelegate` |
| **Entitlements Required** | `carplay-audio` + `carplay-video` | `carplay-audio` + `carplay-video` (Profile `0dc0a173-ef93-4b68-b853-93a9c7958223`) |
| **Web Engine** | `WKWebView` (YouTube mobile) | `WKWebView` with modern Safari User Agent & inline media |
| **Input Routing** | Touch & scroll only (no text entry on car) | Direct touch, scrolling, plus **custom floating QWERTY keyboard** (`CarPlayFloatingKeyboardView`) |
| **Address / Navigation** | Handled via phone relay | Independent car toolbar: address field, back, forward, reload, home, bookmarks bar |
| **Automotive Safety** | `CarGate` (CLLocation speed > 3.0 m/s blanks video) | `SatelliteHUDService` integration (> 11 km/h pauses video with safety overlay) |
| **IPTV / Media Player** | None (browser-only app) | Fully preserved via native `CPTemplateApplicationScene` & `PlaybackManager` |

---

## 3. DrivePlay Architecture Upgrades

### 3.1 Scene Manifest Registration (`project.yml` & `Info.plist`)
`UIWindowSceneSessionRoleCarPlay` is registered alongside existing roles:

```yaml
UIApplicationSceneManifest:
  UIApplicationSupportsMultipleScenes: true
  UISceneConfigurations:
    UIWindowSceneSessionRoleCarPlay:
      - UISceneConfigurationName: "CarPlay Window Configuration"
        UISceneClassName: "UIWindowScene"
        UISceneDelegateClassName: "CarTV.CarPlayWindowSceneDelegate"
    CPTemplateApplicationSceneSessionRoleApplication:
      - UISceneConfigurationName: "CarPlay Configuration"
        UISceneDelegateClassName: "CarTV.CarPlaySceneDelegate"
    UIWindowSceneSessionRoleExternalDisplayNonInteractive:
      - UISceneConfigurationName: "External Display Non-Interactive"
        UISceneDelegateClassName: "CarTV.ExternalDisplaySceneDelegate"
    UIWindowSceneSessionRoleExternalDisplay:
      - UISceneConfigurationName: "External Display"
        UISceneDelegateClassName: "CarTV.ExternalDisplaySceneDelegate"
```

### 3.2 Dynamic Scene Routing (`CarTVApp.swift`)
In `AppDelegate.swift`, incoming connecting scene sessions are routed cleanly:
```swift
if connectingSceneSession.role.rawValue == "UIWindowSceneSessionRoleCarPlay" {
    NSLog("DRIVEPLAY AppDelegate returning CarPlay Window Configuration for role: %@", connectingSceneSession.role.rawValue)
    let config = UISceneConfiguration(name: "CarPlay Window Configuration", sessionRole: connectingSceneSession.role)
    config.delegateClass = CarPlayWindowSceneDelegate.self
    return config
} else if connectingSceneSession.role == .carTemplateApplication {
    let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
    config.delegateClass = CarPlaySceneDelegate.self
    return config
}
```

### 3.3 The CarPlay WebKit Controller (`CarPlayWindowSceneDelegate.swift`)
The new controller `CarPlayWebViewController` provides:
1. **Real `WKWebView`**: Configured with `allowsInlineMediaPlayback = true`, unrestricted JavaScript execution, and custom Mobile Safari User Agent.
2. **Top Automotive Navigation Toolbar**:
   - `backButton` (`chevron.left` with KVO state tracking)
   - `forwardButton` (`chevron.right` with KVO state tracking)
   - `homeButton` (`house.fill` navigates to Google)
   - `addressField` (`UITextField` styled for automotive touch)
   - `keyboardToggleButton` (`keyboard` toggles floating keyboard)
   - `reloadButton` (`arrow.clockwise` / `xmark` when loading)
3. **Quick-Access Bookmarks Bar**: Scrollable chip bar for Google, YouTube, Twitch, Wikipedia, Reddit, Pluto TV, and Hacker News.
4. **Estimated Progress Bar**: Green automotive `#00D066` indicator tracking page load progress.
5. **On-Screen Floating QWERTY Keyboard** (`CarPlayFloatingKeyboardView`):
   - Fully interactive touch keyboard designed for CarPlay displays.
   - Letters, numbers, space, `.com`, `https://`, backspace, clear, and "Go".
6. **Vehicle Motion Safety Lock**:
   - Monitored via `SatelliteHUDService.shared.$currentSpeedKmh`.
   - Speed > 11.0 km/h presents an automotive safety banner and pauses all `<video>` elements.
   - Resumes seamlessly when the vehicle stops.
7. **Process Termination Recovery**:
   - `webViewWebContentProcessDidTerminate` automatically handles WebKit memory terminations and reloads the active webpage.

---

## 4. Verification & Device Test Results

### 4.1 Compile Check (Offline, Video Entitlement)
```bash
xcodebuild -project CarTV.xcodeproj -scheme CarTV \
  -destination 'generic/platform=iOS' -configuration Debug \
  CARPLAY_CATEGORY=video build-for-testing
```
**Result:** `** TEST BUILD SUCCEEDED **`  
Provisioning profile `0dc0a173-ef93-4b68-b853-93a9c7958223` confirmed carrying `com.apple.developer.carplay-video` and `com.apple.developer.carplay-audio`.

### 4.2 Physical Device Test Execution (iPhone 13 `00008110-001C60423CB8401E`)
```bash
xcodebuild -project CarTV.xcodeproj -scheme CarTV \
  -destination 'id=00008110-001C60423CB8401E' -configuration Debug \
  CARPLAY_CATEGORY=video test \
  -only-testing:CarTVTests/BrowserOwnershipAndRoleTests
```

**Hardware Test Results:**
```
Test Suite 'Selected tests' passed at 2026-11-16 11:16:18.330.
	 Executed 9 tests, with 0 failures (0 unexpected) in 1.879 (1.893) seconds
** TEST SUCCEEDED **
```

**Individual Test Verification:**
1. `test_carplay_actions_preserve_handset_tab_selection`: **PASSED**
2. `test_carplay_address_bar_independent_from_handset_active_url`: **PASSED**
3. `test_in_car_automotive_controller_interactive_mode`: **PASSED**
4. `test_in_car_automotive_controller_non_interactive_mode`: **PASSED**
5. `test_screen_relay_car_requested_page_does_not_start_relay`: **PASSED**
6. `test_carplay_tabs_honest_naming_and_icons`: **PASSED**
7. `test_carplay_window_scene_role_registered_in_info_plist`: **PASSED**
8. `test_carplay_web_view_controller_lifecycle_and_components`: **PASSED**
9. `test_carplay_floating_keyboard_delegate_interaction`: **PASSED**

**Hardware Confirmation:**
Real WebContent process spawned and confirmed in test console logs on device:
```
[Process] WebContent process (0x119078680) took 1.744510 seconds to launch
[Process] WebContent process (0x119078c40) took 1.622908 seconds to launch
```

---

## 5. Limitations & Platform Boundaries

1. **System Software Keyboard Unavailable in In-Car Window Scenes:**
   UIKit does not pop up the default system iOS keyboard on CarPlay window scenes. To resolve this, DrivePlay utilizes `CarPlayFloatingKeyboardView`, providing a custom on-screen QWERTY touch keyboard.
2. **Safe Area & Head-Unit Sidebar:**
   CarPlay screens have a persistent system status bar/dock (usually on the left side or bottom). All browser UI constraints anchor to `view.safeAreaLayoutGuide`, ensuring the browser controls never clip underneath the CarPlay dock.
3. **Vehicle Motion Safety:**
   Playing video while driving is restricted by automotive safety regulations. DrivePlay enforces automatic pausing and a safety overlay whenever vehicle speed exceeds 11 km/h.

---

## 6. Rollback Instructions

If it is ever desired to revert exclusively to standard `CPTemplateApplicationScene` without the window scene role:
1. In `project.yml`, remove the `UIWindowSceneSessionRoleCarPlay` dictionary block under `UIApplicationSceneManifest`.
2. In `CarTV/Sources/App/CarTVApp.swift`, remove the `if connectingSceneSession.role.rawValue == "UIWindowSceneSessionRoleCarPlay"` branch.
3. Delete `CarTV/Sources/App/CarPlayWindowSceneDelegate.swift`.
4. Run `xcodegen generate`.
