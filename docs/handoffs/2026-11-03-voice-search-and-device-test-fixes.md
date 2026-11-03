# Handoff — the voice search, the player's audio session, and the device tests (2026-11-03)

Follows `2026-11-03-carplay-four-tab-redesign-and-car-switch.md` (the four tabs,
the car/phone switch).

## 1. What changed

### The voice search never listened (the user's screenshot)

The sheet said *"The operation couldn't be completed. (com.apple.coreaudio.avfaudio
error 1852797029.)"*. The number is `0x6E6F7065` — *"nope"* — and the underlying
call was `PerformCommand(*ioNode, kAUStartIO)`. The cause: **the recorder's
`AVAudioEngine` was born on the player's session**. The player holds the session
as `.playback`, a category with **no input route**, so the engine's input node
reported `channels=2 rate=0.0` and refused to start.

`CarTV/Sources/Services/VoiceSearchManager.swift`:

- the session is handed to the microphone **before** the engine is built
  (`.record`, `.measurement`), and the engine is built **for** the recording;
- a format of `rate 0` / `0 channels` is refused with a message of its own;
- `stopRecording()` gives the player its session back
  (`PlaybackManager.shared.setupAudioSession()`) — a video that is playing has to
  get its sound back with it.

`CarTV/Sources/Views/Home/VoiceSearchOverlayView.swift` no longer shows the raw
system text; it shows *"The microphone could not be opened."* and the log keeps
the original.

### The player's audio session was never configured

`setCategory(.playback, mode: .moviePlayback, options: [.allowBluetooth,
.allowBluetoothA2DP, .allowAirPlay])` throws **OSStatus -50**: those options are
only valid with `.playAndRecord`, so the system refused the whole call and
`setActive(true)` was never reached. The session was therefore **never
activated** — and an inactive session never offers the AirPlay route to the car's
display. Measured on the phone: `.playback` accepts **no options at all**.
`PlaybackManager.setupAudioSession()` now sets the category without options.

### The tests that could not run on a phone

- **A test that reads the repository** cannot run on a device: `#filePath` is
  baked in at build time and points at the Mac. `RepositoryFixture` skips those
  seven contract tests when the checkout is not on the machine.
- **AC47 ("a relay that cannot listen")** took a port that was *not* bound
  (`NWListener(using: .tcp, on:)`), which on a phone asks the system for the
  **local-network permission** and then waits for the answer — the expectation
  never came. The blocker now listens on the **loopback** interface, like the
  app's own relay, and the port is really taken.
- **AC34 ("a capture without frames falls back to the demo")** cannot be
  produced on a phone: ReplayKit waits for the user's consent and never ends on
  its own, so the share sat in `.starting` for ever. The capture is now a seam
  (`ScreenShareService(capture:)`), so the test drives a capture that ends
  without a frame — the same way AC30 already drives `captureAvailable: false`.

## 2. Tests

New: `CarTV/Tests/VoiceSearchTests.swift` (AC67, AC68),
`CarTV/Tests/RepositoryFixture.swift`.

**On the phone** (`scripts/device_test.sh`, iPhone 13, iOS 27): AC67 and AC68
pass — the microphone is taken from the player and the player's session comes
back.

The device build and the device test build are green with these changes:

```
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphoneos \
  -destination 'generic/platform=iOS' -configuration Debug CARPLAY_CATEGORY=video \
  build / build-for-testing
→ ** BUILD SUCCEEDED ** / ** TEST BUILD SUCCEEDED **
```

The written review of the whole codebase is `docs/review-2026-11-03.md`.

## 3. Still open

* **The phone left the USB bus mid-session** (it shows as `unavailable`), so the
  re-run of the two fixed device tests and the screenshots of the car's screen
  are waiting for it. The suite is queued and starts by itself when it is back.
* **`git init` + a first commit** — the project is **not** a git repository.
* **`UIBackgroundModes: audio`** normally wants the
  `com.apple.developer.avfoundation.multitasking` entitlement, which the
  CarPlay entitlements files do not carry. Changing the entitlements risks the
  signing chain, so it is left alone and reported instead.
* **`docs/handoffs/2026-11-03-carplay-video-flip-in-the-portal.md`** still
  describes the profile as lacking the video entitlement; it carries both now
  (a note at the top of that file says so).
