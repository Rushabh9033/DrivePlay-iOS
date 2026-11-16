# Session: 2026-11-16 — the black screen, and the car's own browser

## Goal
The user's brief (a third-party review of the browser work): **real car-side
WebKit rendering**, not a list of websites. The order: preserve the working
app → prove the display architecture → implement only after rendering is
proven → validate at runtime.

## Branch / state
`feature/car-browser-real-surface` (branched from `main` @ `fb94d66`).
- `91acf50` — the in-flight state, preserved
- `79ecf97` — **the black-screen fix (AC177) + the vehicle-window probe**

## Done

### The black screen is fixed (the crash behind it)
The scene delegates carried `@objc(Name)`, which gives a class the runtime name
**without** the module prefix, while the manifest asks for
`CarTV.CarPlaySceneDelegate` → `NSClassFromString` → **nil** → a scene built
from the manifest (the **car launching the app**) gets **no delegate** →
CarPlay raises an NSException in
`-[CPTemplateApplicationScene _deliverInterfaceControllerToDelegate]` →
SIGABRT → the app dies → the phone's window is black. Three crashes two
seconds apart = the system relaunching the app in a loop.

- The `@objc` attributes are gone; the built binary's `__objc_classname`
  section now holds `_TtC5CarTV20CarPlaySceneDelegate` (the module-qualified
  runtime name the manifest asks for).
- **AC177** reads the **running** app's manifest on the device and asserts
  every delegate name resolves — **green on the physical iPhone 13**.

### The experimental vehicle window is registered and probed
- The role is real: CarDash (a shipping CarPlay app) declares
  `"UIWindowSceneSessionRoleCarPlay"` → `UIWindowScene` →
  `"HiCar.CastVehicleWindowScene"`, and UIKitCore exports the private symbol
  `__UIWindowSceneSessionRoleCarPlay` (`UIKit.tbd:20583`). The SDK declares
  **no** such role in any header, and CarPlay has **no** web template:
  `CPInterfaceController` takes only `CPTemplate`s.
- `CarPlay/Sources/App/CarPlayWindowProbe.swift`: a visible `UIWindow` + a real
  `WKWebView` on example.com + a Close control, logging
  `DRIVEPLAY-WEB scene connected role=…`.
- The role is in `project.yml`'s manifest; the probe asks for it when the
  CarPlay template scene connects.

### The security finding
`CarBrowserStream` logged complete URLs (a query string can carry a token) —
both lines now go through `CredentialRedactor.safeForLog`.

## The user's data
- Backed up to `build/userdata_backup_20261116-152659/` (the vault video, the
  index, the preferences).
- **`Documents/saved_channels.json` was already gone** — the reinstall at 13:27
  wiped it, so the playlist catalogue has to be re-added. The Keychain may
  still hold the credentials.
- `backup_user_docs/` (the user's own backup) is now git-ignored.

## In progress / blocked
1. **The experiment**: does iOS deliver the experimental vehicle window to this
   app? The CarPlay Simulator is attached ("CarPlay Simulator - Rushabh's
   Iphone") and its car display is AX-readable (app icons carry their SF
   Symbol as `AXIdentifier`, so a tap can be made **by name**). The car session
   came alive (`CARSessionScreenBecameAvailableNotification`), but the app's
   CarPlay scene has not connected yet, so the probe has not been asked.
   **Waiting on one tap on the car display** (the user's rule: I do not click
   the car display).
2. **A second crash**, from the user's own in-flight build:
   `CarTV-2026-11-16-150000.ips` — CarPlay's
   `clientExceededHierarchyDepthLimit` → SIGABRT, originator
   **CarPlayTemplateUIHost** (the car launched the app). A different bug from
   the delegate name; the app handed CarPlay a template hierarchy too deep.

## The honest limit (from CarDash's own copy)
> "Due to CarPlay interaction limits on iOS 27.2 and later, you can view
> webpages on your car display, but **tapping and scrolling require your
> iPhone**."

So even with the vehicle window, the **car-side touch** is policy-restricted on
iOS 27.2+: the phone is the control surface. The mechanism DrivePlay has
today — the page's real pixels as a **video** the car plays
(`CarBrowserStream`: window-less `WKWebView` → snapshot → HLS → `AVPlayer` →
the car's video route) — stays the fallback, and it is the one that works
without any private API.

## Next
1. **One tap on the car display** (DrivePlay in the CarPlay Simulator's app
   grid). Then read `build/live_capture.log` for:
   - `DRIVEPLAY CarPlay scene connected` → the template scene is up and the
     crash is gone;
   - `DRIVEPLAY-WEB asking for the vehicle window (role=UIWindowSceneSessionRoleCarPlay)`
     then either `scene connected` (**the experimental window exists — Phase C
     can go ahead**) or `the vehicle window was refused` (it does not — the
     answer is then the video path, and the brief's "report what is blocked"
     applies).
2. Phase C, only if the window exists: install
   `~/Desktop/DrivePlay-CarBrowser-Rebuild/CarTV/Sources/App/CarPlayWindowSceneDelegate.swift`
   — it needs a `CarPlayFloatingKeyboardView` (the package expects DrivePlay to
   already have one; this tree does not) and it was **never compiled against
   the iOS SDK**.
3. The hierarchy-depth crash (item 2 above).
