# Handoff — the broadcast picker, and the iOS 27 check on a real phone (2026-11-02)

This is the second half of today's work. The first half is in
`2026-11-02-carplay-simulator-video-surface.md` (the CarPlay Simulator draws the
picture, and the crash that could kill the app).

## 1. What this half settled

**The broadcast can now be started from the app — the WhatsApp flow.** Until
now the app could only *wait* for a broadcast: the user had to find the
Control Center and start "DrivePlay Screen Relay" by hand. The app cannot
start a broadcast by itself (iOS always asks the user), but it can put the
system picker in front of the user. One tap on the app's button, one tap on
the relay in the system list, and the phone's screen is on the car.

**Two corrections to what was believed before:**

* *"`RPSystemBroadcastPickerView` is removed from the iOS 27 SDK."* **It is
  not.** It is present in the device **and** the simulator SDK, deprecated with
  *"Use ScreenCaptureKit SCContentSharingPicker instead"* (`ios(12.0, 27.0)`) —
  a different message from the *"No longer supported"* of the rest of the
  family. Its deprecation version is above the app's deployment target (18.0),
  so it compiles **without a deprecation warning**.
* *"ScreenCaptureKit is the iOS 27 successor, so the broadcast extension is on
  its way out."* On iOS it cannot replace it: `SCShareableContent` is
  `API_UNAVAILABLE(ios)`, so an iOS app cannot enumerate another app's windows
  or displays, and the only iOS picker is
  `presentPickerForCurrentApplication` — the app's **own** screen. The upload
  extension is the only mechanism that can mirror another app to the car.

**A bug in the relay, found on the way.** `startRelay()` stopped the share
that was already running — but the relay only *listens*; it shares nothing
until the extension announces its stream. The contract was already written down
("the relay now only listens: the share state is untouched until a stream
really arrives") and the code did the opposite. That also made it impossible
to leave the relay listening while the user picks the broadcast in the picker.
The eager stop is gone; the broadcast replaces the running share in
`playRelay`, when it arrives.

## 2. What changed

| File | Change |
|------|--------|
| `CarTV/Sources/Views/Cast/CastToCarView.swift` | The system broadcast picker, offering only the app's own extension. The relay starts listening as soon as the share card appears, so the extension finds the app when the user picks it. |
| `CarTV/Sources/Services/ScreenShareService.swift` | `startRelay()` no longer stops the running share. `broadcastExtensionIdentifier` is derived from the app's own bundle identifier, so the picker can never point at the wrong extension. |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | The row's detail text points at the app instead of the Control Center. |
| `CarTV/Tests/ScreenShareTests.swift` | **AC43**: the relay listens without disturbing a running share. **AC44**: the picker points at the app's own extension. |
| `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md` | The two new criteria, the picker, the relay fix, and the corrected facts about ReplayKit and ScreenCaptureKit on iOS 27. |

## 3. The real phone

A **connected iPhone 13 running iOS 27.0** (Developer Mode on) was found
attached, so the device build was made and installed on it:

```
xcodebuild -sdk iphoneos -destination 'id=<udid>' -allowProvisioningUpdates build
scripts/auto_install.sh          # installed, no crash log on the device
```

The build carries the **audio** CarPlay category — the video capability still
has to be granted by Apple (`docs/carplay-video-request.md`) — and the
`ScreenRelay.appex` is embedded with the right extension point
(`com.apple.broadcast-services-upload`, `RPBroadcastProcessModeSampleBuffer`).

**What is still unverified on the device, and needs one tap:** whether iOS 27
still launches an upload extension at all. The picker shows the system list;
if "DrivePlay Screen Relay" is in it, the extension point survives and the
whole flow works. If the list is empty, mirroring another app's screen to the
car is impossible on iOS 27 — the app's *own* content on the car's video
surface still works.

## 4. Still open

* **Apple's grant** — one click by the account admin (Identifiers → App ID →
  Capabilities → CarPlay Video on, CarPlay Audio off). Until then the device
  build signs with the audio category and the car keeps working as it does
  today. `docs/carplay-video-request.md` is the package to send.
* **The CarPlay Simulator** is attached by hand (Xcode's Device Hub — there is
  no CLI). Tap "Screen Mirroring" on the car and the demo picture travels the
  same chain as a real share.
* **The broadcast on the device** — the one tap described above.
* **No device test of the car picture.** The chain is verified by the unit
  tests (AC29–AC32) and the Simulator build; the broadcast → car path has not
  run on hardware.

## 5. Verification

```bash
./scripts/run_tests.sh     # 66 tests, 0 failures, no crash markers
```

Read the log for `Terminating app` as well as the exit code: xcodebuild
re-runs a suite after a host crash, so a green exit code can be the retry.
