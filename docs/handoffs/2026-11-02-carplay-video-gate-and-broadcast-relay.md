# Handoff — CarPlay video gate, broadcast screen share, one knob for the category

**Date:** 2026-11-02
**Session:** 1-hour autonomous window ("i am going outside and will be return in 1 hour")
**Device state:** the iPhone was with the user, so **nothing was installed or run on a device**. Everything below was verified on the Simulator and on the signing pipeline.

---

## 1. The request

> "did u found the way to counter both audio and video together ?? if yes then make more improvements"

Two things were asked for: **audio and video together on the car's display**, and the
screen mirroring done **"broadcasting like in whatsapp video call we can screen share
(same to same)"**.

## 2. What was actually blocking it (measured, not guessed)

Two *independent* blockers, both measured on the physical iPhone (iOS 27.0) before the
changes below:

**Blocker A — the entitlement, not the code.** The CarPlay rows asked for
`CPPlaybackPresentation.video`, and the system refused the playback:

```
CarPlayTemplateUIHost(CarPlaySupport) <Error>: cannot prepare playback:
presentation is video but app does not have the video entitlement
```

The capability is granted to the team (`Case-ID 23260500`, App Type **VIDEO**), but the
**app id** still lists CarPlay **Audio**, so the provisioning profile carries
`com.apple.developer.carplay-audio` only. Xcode cannot fix this from the command line —
with `-allowProvisioningUpdates` it reaches the portal (it mints profiles) but refuses to
put `CARPLAY_VIDEO` on an app id: it falls back to the wildcard profile
(`XC Wildcard`, `application-identifier 47T499AR2T.*`, no CarPlay keys). Two brand-new
bundle ids behaved the same. **The flip has to be done in developer.apple.com.**

**Blocker B — ReplayKit refuses to record while CarPlay is connected.**

```
RPRecordingErrorCarPlay = -5813   // Failed to start recording due to carplay being active
```

The screen share was built on `RPScreenRecorder.startCapture`, which is called from the
car — where CarPlay is *always* active. So the capture could never produce a frame, and
the app silently fell back to the **demo picture**: the driver saw a fake animation and
believed it was their phone's screen.

**The answer to "how does the original app have audio + video?"** — Apple's mail says the
CarPlay **Audio** entitlement "has been extended to support cases where both audio and
video content are combined in a single app", and that both entitlements in one app are
not supported. On iOS 27.0 the measured behaviour is that the `.video` presentation is
gated on the **video** entitlement specifically, so: one entitlement key at a time, and
the app must ask CarPlay only for what it is signed with. That is what the code now does.

## 3. What changed

| File | Change |
| --- | --- |
| `project.yml` | New build setting `CARPLAY_CATEGORY` ("audio"/"video"). It picks the entitlements file **and** the `CarPlayCategory` Info.plist key, so the app and the signature can never disagree. `Shared/` is compiled into the app **and** the extension. |
| `CarTV/Resources/CarTV.audio.entitlements` (new) | `com.apple.developer.carplay-audio` — the default, so the device build signs and installs today. |
| `CarTV/Resources/CarTV.video.entitlements` (new) | `com.apple.developer.carplay-video` — used after the portal flip. |
| `CarTV/Resources/CarTV.entitlements` | **deleted** — one file per category now. |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | Rows ask for `.video` **only** when the build is entitled; otherwise `.audio` (the now-playing screen), which is what actually works. The "Screen Mirroring" row starts the **relay** instead of the doomed in-app capture. |
| `CarTV/Sources/Services/ScreenShareService.swift` | New `startRelay()` (wait for the broadcast and play it); the CarPlay recording failure now says what to do instead of failing silently. |
| `CarTV/Sources/Services/ScreenRelayListener.swift` (new) | The app's end of the relay channel — a listener bound to the loopback interface. Starting it twice does nothing, so a restart cannot drop an announcement on its way. |
| `ScreenRelay/SampleHandler.swift` | Was a stub. Now encodes the broadcast's frames into a live HLS stream, serves it, and tells the app where the stream is. |
| `Shared/LiveScreenStream.swift` (new) | The encoder, the server and the frame scaler, moved out of the app so the extension can use them too. |
| `scripts/carplay_grant.sh` | Reads the category's entitlements file; **and a real bug is fixed**: `check` always said MISSING (the profile folder has a space in its name and was word-split, and `pipefail` + `grep -q` turned a good profile into a failed one). |
| `CarTV/Tests/*` | AC27 rewritten, AC35/AC36/AC37/AC38 added (category agreement, the video gate, the relay announcement in both directions). |

**How the broadcast reaches the car**

```
Control Center → DrivePlay Screen Relay  →  the extension encodes the screen
                                             and serves it as live HLS
                    ↓  (loopback, one line: "<port> <token>")
                    the app picks the stream up and plays it
                    ↓
                    the car's now-playing area draws what the app plays
```

The two processes share no container (an App Group would need another Apple-granted
capability), so the stream address travels over the loopback interface. The extension
retries the announcement for five minutes, so the broadcast may be started **before** the
row is tapped.

**The relay only listens — it never latches the share state.** It waits without holding
the "starting" state, so the phone's own share controls stay usable and the phone says
what it is waiting for. It also survives the end of a share: the listener lives as long as
the car is connected and stops when the CarPlay scene disconnects. (Both were bugs: the
share buttons stayed disabled for as long as the car waited, and the next broadcast was
not picked up until the row was tapped again.)


## 4. What still needs the account holder — one click

1. <https://developer.apple.com/account/resources/identifiers/list> → App ID
   `XC com rushabh cartvv` → **Capabilities**.
2. Turn **CarPlay Audio** off and **CarPlay Video** on (both at once is not supported).
3. Save, then tell the developer — or run it yourself:
   ```bash
   CARPLAY_CATEGORY=video scripts/carplay_grant.sh grant
   ```
   and check the result with `CARPLAY_CATEGORY=video scripts/carplay_grant.sh check`.

Until then `CARPLAY_CATEGORY` stays `"audio"`, the app signs with the audio entitlement,
and the car keeps working exactly as it does today (audio + now-playing, verified).

**The flip cannot be done from the command line — that is now measured, not guessed.**
Xcode's own "Update Signing" HTTP transcript (in
`~/Library/Developer/Xcode/DerivedData/CarTV-*/Logs/Update Signing/*.xcactivitylog`) shows
the three portal calls it makes: two reads (`GET bundleIds`, `GET bundleIds/{id}?include=
bundleIdCapabilities.capability`) and one profile mint. The profile payload carries **no
entitlements array** — the portal derives the profile's entitlements from the app id's
`bundleIdCapabilities`, which for `ZS47M4AZ77` are exactly `CARPLAY_PLAYABLE_CONTENT` and
`IN_APP_PURCHASE`. `CARPLAY_VIDEO` occurs 0× in both logs. `xcodebuild -help` has no
capability command; `fastlane`/`spaceship` are not installed; the private API
(`DVTPortalAppID createAppIDWithSession:team:bundleID:features:…`) has no CLI front-end.

**No Apple request form is needed for the video entitlement.** The team's own capability
catalogue
(`~/Library/Developer/Xcode/UserData/Capabilities/capabilities-27.0-47T499AR2T-bundle.json`)
carries the entry:

```
id: CARPLAY_VIDEO   name: "CarPlay Video"
entitlements: [ { profileKey: "com.apple.developer.carplay-video", valueType: BOOLEAN } ]
canRequestFromPortal: false   editable: true   distributionApprovalRequired: false
```

`canRequestFromPortal: false` means there is no request form to send (unlike
`CARPLAY_AUDIO_APP` and `CARPLAY_COMMUNICATION`, which have
`requestFormUrl: https://developer.apple.com/contact/request/carplay/`) — the capability
was already granted to the team (Case-ID 23260500, App Type **VIDEO**), it just has to be
ticked on the app id. `editable: true` means the portal lets you tick it yourself.

## 4a. The iOS 27 catch — the broadcast mechanism Apple is retiring

The phone runs **iOS 27.0**, and in that SDK the whole ReplayKit broadcast family is
deprecated with *"No longer supported"*
(`ios(10.0, 27.0)`): `RPBroadcastSampleHandler` (the base class of the upload extension
this project uses), `RPBroadcastActivityViewController`, `RPBroadcastController`,
`RPSystemBroadcastPickerView` (*"Use ScreenCaptureKit SCContentSharingPicker instead"*).
`RPScreenRecorder` is deprecated as well — but it still runs, which is how the -5813
measurement was possible. **A deprecation message is not a removed API**, so the
`ScreenRelay` extension may well still be launched on iOS 27; it has to be tried on the
device.

**If the extension is not launched, the successor is ScreenCaptureKit**, and the work is
smaller than the broadcast relay:

* `SCContentSharingPicker` is `API_AVAILABLE(ios(27.0))` — new in iOS 27.
  `presentPickerForCurrentApplication()` is the iOS-only entry point;
  `SCContentSharingPicker.sharedPicker.defaultConfiguration` carries
  `showsMicrophoneControl` / `showsCameraControl` (iOS 27).
* `SCStream` + `SCStreamOutput` deliver `CMSampleBuffer`s — the same
  `CVPixelBuffer` the encoder already takes, so the frames go straight into
  `LiveScreenWriter` → `ScreenStreamServer` → `PlaybackManager.playScreenShare`, and
  **no relay is needed at all** (the capture is in-process).
* **ScreenCaptureKit does not exist in the Simulator SDK** (only in the iPhoneOS SDK) and
  every symbol is iOS 27+, so the code has to sit behind
  `#if canImport(ScreenCaptureKit)` **and** `#available(iOS 27.0, *)`. It can only be
  compile-checked with `xcodebuild -sdk iphoneos build`; the Simulator build compiles the
  branch out, and the CarPlay Simulator therefore keeps the demo picture.
* Whether ScreenCaptureKit is blocked while CarPlay is connected is **not measurable
  without a device** — the -5813 refusal is a ReplayKit error code, and the iOS 27
  ScreenCaptureKit path is a different implementation.

That is the one open question the device answers.

## 5. How to test when the phone is back

```bash
# 1. build and install (the phone has to be connected and trusted)
./scripts/auto_install.sh            # or: xcodebuild … -destination id=<udid> build
# 2. the app asks for video as soon as it is signed with the video entitlement:
plutil -p build/Build/Products/Debug-iphoneos/CarTV.app/Info.plist | grep CarPlayCategory
#    CarPlayCategory => "video"      ← only after the portal flip
```

* **Audio + video on the car:** with `CarPlayCategory => "video"`, pick a channel on the
  car — the picture appears in the now-playing area (the car's video surface), next to
  the artwork and the transport buttons that already work.
* **Screen mirroring:** install once, then on the phone
  **Control Center → Screen Recording → DrivePlay Screen Relay → start broadcast**,
  then on the car **DrivePlay → Screen Mirroring**. The row waits for the broadcast; the
  phone's screen appears on the car.

## 6. Not verified (and why)

* **No device test.** The iPhone was with the user for the whole session. The relay
  chain is verified by unit tests (announcement in both directions) and by a clean
  Simulator build of both targets, but the *broadcast → car* path has not been run on
  hardware.
* **The broadcast extension on iOS 27 is unproven** — Apple deprecated the whole
  ReplayKit broadcast family in that OS ("no longer supported", §4a). If the extension
  is not launched any more, the successor is ScreenCaptureKit (`SCContentSharingPicker`
  + `SCStream`, iOS 27+, device-only) and the capture would be in-process, which is
  *less* code than the relay — but it can only be compile-checked against the device
  SDK and only run on the phone.
* **The relay carries no audio.** The stream is video only; the phone's system audio is
  not part of the HLS playlist. The car's audio comes from the app's own playback (the
  channels), which is unaffected.
* **`CPSessionConfiguration.supportsVideoPlayback` is not reachable** from the public
  CarPlay headers (no public accessor), so the app cannot ask whether the *car* supports
  video. It does not have to: `.video` means "present video if available, otherwise show
  now playing".
* **The audio entitlement might also carry video.** Apple's mail says the CarPlay Audio
  entitlement now supports combined audio and video content. On iOS 27.0 the measured
  behaviour is a refusal (see §2), so the code follows the measurement. If a later iOS
  lifts it, the gate can be relaxed — one line in `CarPlaySceneDelegate.playbackConfiguration`.

## 7. Verification performed

* `xcodebuild … -sdk iphonesimulator build` → **BUILD SUCCEEDED** (app + `ScreenRelay.appex`).
* `./scripts/run_tests.sh` → **62 tests, 0 failures** (was 56 at the start of the
  session; AC35–AC38 and AC39–AC40 are new).
* Built app entitlements (Mach-O `__TEXT,__entitlements`, decoded from the byte-swapped
  dump): `com.apple.developer.carplay-audio` — the audio category, as intended.
* Built `Info.plist`: `CarPlayCategory => "audio"` — the `$(CARPLAY_CATEGORY)` expansion
  works in both the entitlements path and the Info.plist.
* `scripts/carplay_grant.sh check` → `OK com.apple.developer.carplay-audio — carried by
  2d988fdc-…mobileprovision`; with `CARPLAY_CATEGORY=video` → `MISSING
  com.apple.developer.carplay-video`, which is the one portal step left.
* `xcodebuild … -destination 'generic/platform=iOS' -allowProvisioningUpdates build` →
  **BUILD SUCCEEDED**: the **device** build signs with the audio profile, so the app
  installs again. (Run twice — before and after the relay changes.)
