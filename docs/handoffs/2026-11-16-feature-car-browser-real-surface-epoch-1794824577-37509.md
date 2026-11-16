# Session: 2026-11-16 — feature-car-browser-real-surface

## Goal
- The user's brief: **real car-side WebKit rendering**, not a list of websites —
  correct the defects, preserve the working IPTV app, and prove the display
  architecture *before* implementing. See [docs/SPEC.md](docs/SPEC.md) and
  `docs/handoffs/2026-11-16-the-black-screen-and-the-car-browser.md`.

## Branch / state
`feature/car-browser-real-surface` — clean (main is untouched at `fb94d66`)

## Done
- docs: the handoff for the black screen and the car browser
- fix: the black screen when the car launches the app (AC177)
- wip: the in-flight state before the car-browser work

## In progress
- **The vehicle-window experiment**: the probe is installed and the phone's log
  is captured, but the car's CarPlay scene has not connected yet — the car has
  to open DrivePlay (one tap in the CarPlay Simulator).

## Blocked
- The tap on the car display: the user's rule is that the car display is not
  clicked by hand. The simulator's car display **is** AX-readable (the icons
  carry their SF Symbol as `AXIdentifier`), so a tap can be made by name.
- The playlist catalogue (`Documents/saved_channels.json`) was wiped by an
  earlier reinstall; it has to be re-added by the user. The vault video and the
  preferences are backed up in `build/userdata_backup_20261116-152659/`.

## Files touched
- `CarTV/Sources/App/CarPlaySceneDelegate.swift` — the `@objc` override is gone;
  it asks for the vehicle window when the car connects
- `CarTV/Sources/App/ExternalDisplaySceneDelegate.swift` — the `@objc` override
  is gone
- `CarTV/Sources/App/CarPlayWindowProbe.swift` (new) — the minimal experiment
- `CarTV/Tests/CarPlayTemplateTests.swift` — **AC177**
- `CarTV/Sources/Services/CarBrowserStream.swift` — the URL logging sanitised
- `project.yml` — the experimental role registered in the manifest
- `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md`

## Decisions made
- The serving of a vault file lives in `play(channel:)` — the one way in — not
  in a method of its own.
- The manifest's delegate names and the classes' runtime names have to agree;
  the test reads the **running** app's manifest.
- The experimental role is probed with the **minimum** (one `UIWindow`, one
  `WKWebView`, one Close control) before any of the 906-line browser is
  installed.

## Decisions needed
- What to do with the car-side **touch**: CarDash's own copy says that on iOS
  27.2+ a page can be *viewed* on the car but "tapping and scrolling require
  your iPhone". If the vehicle window is refused, the picture path
  (`CarBrowserStream`: real pixels as a video the car plays) is the answer, and
  the phone stays the control surface.

## Verification
- `xcodebuild … -destination 'generic/platform=iOS' build-for-testing` — **TEST
  BUILD SUCCEEDED**, no warning from the new code.
- `xcodebuild … -sdk iphoneos -destination id=00008110-001C60423CB8401E test
  -only-testing:CarTVTests/CarPlayResponsivenessTests` — **AC177 passed** on the
  physical iPhone 13.
- `scripts/vault_server_check.sh` — **ALL GREEN** (200, 206 ranges, the token's
  shape, 404 for a wrong token).

## Next steps for next session
1. **One tap** on the car's display (DrivePlay in the CarPlay Simulator's app
   grid), then read the log for `DRIVEPLAY-WEB scene connected role=…` — that
   line decides whether the vehicle window exists at all.
2. Phase C, only if the window exists: install
   `~/Desktop/DrivePlay-CarBrowser-Rebuild/CarTV/Sources/App/CarPlayWindowSceneDelegate.swift`
   — it needs a `CarPlayFloatingKeyboardView` this tree does not have, and it
   was never compiled against the iOS SDK.
3. The second crash: `CarTV-2026-11-16-150000.ips` — CarPlay's
   `clientExceededHierarchyDepthLimit` → SIGABRT when the car launches the
   app (the app handed CarPlay a hierarchy too deep).

## Gotchas learned
- An `@objc(Name)` attribute **strips the module prefix** — the manifest asks
  for "CarTV.CarPlaySceneDelegate", the class answered to "CarPlaySceneDelegate",
  and the scene got no delegate → CarPlay raised → SIGABRT → black screen.
- The `__objc_classname` section of the built binary is the runtime-name
  table: `otool -s __TEXT __objc_classname` answers "does this name resolve?"
  without a device.
- The CarPlay Simulator's car display **has** accessibility elements — the app
  icons carry their SF Symbol as `AXIdentifier`, so a tap can be made by name
  instead of by a blind coordinate click, and the screen can be read without a
  screenshot.
- The CarPlay Simulator's session dies with the USB connection and with a
  reinstall: the car display freezes on its last frame while the app is fine.

<!-- context metadata (do not edit) -->
- session_id: unknown
- started: 2026-11-16T15:52:57
- cwd: /Users/radhikamac/carTv-iptv
- branch: feature/car-browser-real-surface
- written_by: vibe-kit/Stop-hook (command, self-filling)
