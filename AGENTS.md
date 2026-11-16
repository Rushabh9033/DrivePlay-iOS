# AGENTS.md — DrivePlay / CarTV app

Project-specific rules for this repo. The global `~/.claude/CLAUDE.md` still applies; this file wins on conflict.

## Build & test

**The user's rule: the physical iPhone 13 only.** The iPhone 18 Pro
**Simulator is not to be booted, installed to or installed from** — the
CarPlay video surface, the broadcast and the car's own screens can only be
exercised on the device anyway (Xcode 27's CarPlay Simulator hosts physical
devices only), and a simulator run says nothing about the phone.

A **compile check** (no simulator, no device, nothing booted):

```bash
xcodebuild -project CarTV.xcodeproj -scheme CarTV \
  -destination 'generic/platform=iOS' -configuration Debug \
  CARPLAY_CATEGORY=video build-for-testing
```

**On the phone** (the CarPlay video surface and the broadcast can only be
exercised there, and Xcode 27's CarPlay Simulator hosts physical devices only):

```bash
scripts/device_test.sh          # waits for the phone, then runs the suite on it
```

The phone is `00008110-001C60423CB8401E` ("Rushabh's Iphone"). It drops off
the USB bus when the cable is disturbed — `xcrun devicectl list devices` then
shows it as *unavailable* or *available (paired)*, and
`devicectl device info lockState` fails with *"The tunnel connection failed"*.
A suite run against a destination the phone cannot reach fails with
*"Unable to find a destination matching the provided destination specifier"* —
that is the **cable**, not the code.

**But `available (paired)` is not the same as gone.** A phone that is off the
USB bus is still reachable over **Wi-Fi** when it is paired and on the same
network: `devicectl device info lockState` answers, and `xcodebuild
-showdestinations` lists it as a destination — so the suite runs on it
without the cable at all. A waiter that waits for the literal word
*"connected"* waits for ever over a Wi-Fi link. **Test the link, not the
word**: `devicectl device info lockState` (does the tunnel answer?) or
`xcodebuild -showdestinations` (is it a destination?) — and remember that
*"disconnected"* contains *"connected"*, so a plain `grep` on the device list
matches the wrong state too.

**Other people's devices are not to be used** either ("SG MAC's iPhone",
"Krushi Mac's iPad").

`CarTV/Tests` is a real XCTest target (`CarTVTests`), wired into the `CarTV` scheme.
`@testable import CarTV` needs `ENABLE_TESTABILITY: YES` in the app target's **Debug** config —
it is set in `project.yml`.

- **The test target has to carry its own team.** The Simulator signs ad-hoc and
  never asks, but a device build fails with *"Signing for CarTVTests requires a
  development team"* — the test bundle is installed like any other app. It now
  has `DEVELOPMENT_TEAM` and automatic signing in `project.yml`, like the app.

- **The iOS test bundle cannot spawn processes.** `Foundation.Process` does not exist in the
  iOS SDK ("Cannot find 'Process' in scope", even with `import Foundation`), so a test can
  never run a shell script. Cover repo scripts with a static contract test and exercise the
  runtime behaviour from the shell by hand.

## Gotchas (learned the hard way)

- **`project.yml` is the source of truth for `Info.plist`.** `xcodegen generate` overwrites
  `CarTV/Resources/Info.plist` from `project.yml`. Never hand-edit the plist — it will be
  silently reverted. After editing `project.yml`, run `xcodegen generate` and re-check the plist.
- **A deleted source file needs `xcodegen generate` too.** The generated `project.pbxproj`
  names every source file, so removing one from the disk leaves the build failing with
  *"Build input file cannot be found"* — the file is still in the project. Regenerate
  (`xcodegen generate`) after adding or removing a file, not just after editing `project.yml`.
- **The CarPlay scene configuration name must be `"CarPlay Configuration"`.**
  `AppDelegate.configurationForConnecting` looks up
  `UISceneConfiguration(name: "CarPlay Configuration", sessionRole: .carTemplateApplication)`.
  A name that does not match the plist declaration leaves `sceneClass == nil`, so the scene is
  not a `CPTemplateApplicationScene` and CarPlay silently never connects.
- **The Simulator needs a location grant or the Cockpit card hangs forever.**
  `SatelliteHUDService.isSatelliteConnected` only flips in `didUpdateLocations`, so without a
  fix the card reads "ACQUIRING SATELLITES..." indefinitely:

  ```bash
  xcrun simctl privacy booted grant location com.rushabh.cartvv
  xcrun simctl location booted set 37.3317,-122.0301
  ```

- **`RPScreenRecorder.isAvailable` is `true` on the Simulator, but the capture delivers
  nothing.** Measured on the iPhone 18 Pro Simulator: the flag is true, the capture starts and
  ends again within a second without a single frame, so the share reports *"This device cannot
  record the screen."* The flag alone therefore proves nothing — check it *before* latching
  any state (or the UI wedges on a waiting card that never resolves), and use
  `DemoFrameSource` to exercise the encode/serve/play chain on the Simulator, because it
  feeds the same encoder and the same server.
- **A video-only `AVPlayerItem` never renders without a video output.** With no
  `AVPlayerLayer` attached, CoreMedia logs *"video-only item is waiting for video output"*,
  `timeControlStatus` stays `.waiting`, the playhead never leaves zero and
  `currentTime()` stays at `0` — while the stream itself is perfectly fine (the segment pump
  keeps downloading every fragment). This is what made AC32 fail for a whole session: the
  player was never broken, it had nowhere to draw. Any test that plays video has to attach a
  layer (`AVPlayerLayer` on a view in a `UIWindow`); the app's player view already does.
- **The macOS command line cannot render HLS; the Simulator can.** A probe built for the
  command line reports `status=1, tcs=1, t=0.0` for *every* stream, Apple's own included,
  while the same URL plays in the Simulator. Do not debug an HLS problem on the command line —
  it produces false negatives.
- **AVFoundation fails a player item permanently when it sees an HTTP 503.** There is no
  retry. The screen-share server therefore only publishes its URL once the writer has produced
  a playlist, so the player never sees the "not ready" response.
- **CarPlay renders templates only — never install a view controller.** No public header in
  `CarPlay.framework` references `UIViewController`; the framework exposes `setRootTemplate`,
  `pushTemplate`, `presentTemplate` and `showOverlayTemplate` and nothing else. A CarPlay
  scene delegate that assigns `CPWindow.rootViewController` (or lifts a view with
  `layer.zPosition = 99999`, or keeps it on top with a repeating timer) is fighting the
  framework — the view never renders. `InCarAutomotiveController` is a plain `UIViewController`
  and is legitimate **only** for `ExternalDisplaySceneDelegate` (a normal `UIWindowScene`).
- **`CPListSection` has two initialisers and only one of them takes a `nil`
  header.** The plain one (`init(items:header:sectionIndexTitle:)`) has a
  *nullable* header; the enhanced one
  (`init(items:header:headerSubtitle:headerImage:headerButton:sectionIndexTitle:)`)
  declares `header:(NSString *)` **non-null** — `CPListSection.h` sits inside
  `NS_ASSUME_NONNULL_BEGIN` — so `header: nil` does not compile there. Use the
  plain initialiser for a section without a header.

- **Never call a CarPlay template API without a completion handler.** CarPlay
  **throws an `NSException` when a template call fails and no completion handler
  was given** ("If the template presentation is not successful AND no completion
  block is specified, an exception will be thrown" — `CPInterfaceController.h`).
  An uncaught ObjC exception aborts the process, so a failed call kills the app.
  The app's now-playing crash was exactly this: `presentTemplate` accepts only
  action sheets, alerts and voice control, so presenting `CPNowPlayingTemplate`
  failed — and with `completion: nil` it took the app down on **every** row tap.
  Every template call now carries a handler that logs the failure.
- **The now-playing screen is the system's to present.** The rows carry a
  `CPPlaybackConfiguration`, and CarPlay shows the media presentation itself
  when the item is selected ("the style of media presentation shown after
  selecting the item") — presenting the shared now-playing template on the
  app's behalf. The app only configures `CPNowPlayingTemplate.shared`. It must
  not present one itself: that is both the unsupported-type crash above and the
  thing that would stand between the system and the **video surface**, which
  the system draws in its own now-playing presentation.
- **Video in CarPlay is drawn by the system, never by us.** There is no way to put your own
  video surface on a car screen. The sanctioned signal is
  `CPListItem.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video, …)`
  (iOS 26.4+), which tells CarPlay the row is video and the system presents the picture in the
  now-playing area. Only `CPListItem` carries that property — `CPGridButton` does not — so a
  channel picker that must request video has to be a **list**, not a grid. It still needs the
  Apple-granted `com.apple.developer.carplay-video` capability.
- **The car's screen is a tab bar.** `CPTabBarTemplate(templates:)` takes the templates and
  `CPTabBarTemplateDelegate.tabBarTemplate(_:didSelect:)` tells the app which tab the user
  picked. A tab shows its own name and icon through `CPTemplate.tabTitle` / `tabImage` — the
  **system** paints the bar, the selection marker and the list chrome, so the app's palette
  can only be expressed through the artwork it hands over and the tab icons. That is the whole
  limit of "make it dark and green" on CarPlay.
- **A search result is not a list row either.** `CPSearchTemplate` gives the app the
  results (`searchTemplate(_:updatedSearchText:completionHandler:)`) and takes the selection
  back through `searchTemplate(_:selectedResult:completionHandler:)` — the header says the
  app must call the completion handler *"when you have handled the row selection"*, so the
  row's own `CPListItem.handler` is **not** called for a search result. A delegate that only
  answers the completion handler leaves the car with a search that finds channels and plays
  none of them. The result carries only the channel's name, so the app has to remember which
  channel each result stands for (the item's own identity — `ObjectIdentifier` — is the only
  thing two channels with the same name do not share).
- **A row of cards is not a row of items.** `CPListImageRowItem(text:cardElements:allowsMultipleLines:)`
  (iOS 26+) is the horizontally scrollable card row of the reference interface, but a card row
  is **not** a `CPListItem`: its title lives on `CPListImageRowItemCardElement.title`, and the
  tap comes through `listImageRowHandler` with the **index** of the card. A test (or any code)
  that walks `section.items` looking for a `CPListItem` with the channel's name finds nothing
  on a car that runs iOS 26 — the same channel list is a plain `CPListItem` on an older car.
- **CarPlay trims a template silently.** `CPListTemplate.maximumItemCount` and
  `maximumSectionCount` are the most rows and sections the system shows; anything beyond them
  is dropped **without a word**. A playlist with hundreds of categories therefore loses its
  tail — every channel has to be reachable another way (here: "All", plus a "Show all N
  channels" row per category).
- **An `NWListener` without a connection handler never binds.** `NWListener` started with
  no `newConnectionHandler` and no `newConnectionGroupHandler` logs *"Started without
  setting either new connection handler or new connection group handler"* and **never reaches
  `.ready`** — the socket is not created, so a test that waits for `.ready` waits for ever
  while the port looks perfectly free. The handler is what makes the bind happen (the app's
  own relay sets one for the same reason); a blocker listener in a test needs one too, even
  though it never expects a connection.
- **Artwork is drawn for the car's screen, not the phone's.** *"Images you display in any
  template should be sized to a display scale matching the scale of the
  `carTraitCollection`, not the scale of the iOS device's main screen."* The scale comes from
  `interfaceController.carTraitCollection.displayScale` — read it when the scene connects and
  set it on the renderer (`UIGraphicsImageRendererFormat.scale`). A logo is drawn with
  `AVMakeRect(aspectRatio:insideRect:)` inside the card, so it keeps its own aspect ratio and
  is never stretched or clipped.
- **The CarPlay Simulator is installed at `/Users/radhikamac/Desktop/CarPlay Simulator.app`**,
  not under `Xcode.app/Contents/Developer/Applications/` (Xcode 27 removed `Simulator.app`).
  The correct signal that it exists is the standalone app or the
  `CarPlaySimulator.devicekitplugin` under `DeviceKit.framework` — **not**
  `simctl list devicetypes | grep -i carplay` (that list is always empty) and not a missing
  Xcode applications folder. CarPlay now lives in Xcode's **Device Hub**, which has no CLI:
  `devicectl` has no carplay/session subcommand and the CarPlay Simulator app declares no
  `CFBundleURLTypes`. Attaching a simulator is a one-click Device Hub action.
- **In Xcode 27 the CarPlay Simulator attaches to physical devices only.** Its
  binary has `USBiPhoneDevice` / `AMDeviceConnect` paths and **no**
  `SimDevice`/`CoreSimulator` reference, `DeviceHub.app` has **zero** CarPlay
  strings, and the simulator's `runningboardd` logs *"Error 1 setting Carplay
  mode to 0: Operation not permitted"* for the app. **An iOS Simulator device
  cannot host a CarPlay session** — so the demo picture cannot be seen on a car
  from the Simulator. Driving the car's display also needs a **Quartz
  `CGEvent`** (move → leftMouseDown → hold → leftMouseUp): the display has no
  accessibility elements at all, so a System Events `click at` is ignored.

- **The video surface needs a profile, and a profile needs the portal.** Apple
  granted the **CarPlay Video App** entitlement to the team (Case-ID 23260500),
  but the app id in the portal still carries **CarPlay Audio**, so the one local
  profile for `com.rushabh.cartvv` carries `carplay-audio` and nothing else,
  and `CARPLAY_CATEGORY=video` fails with *"Entitlement
  com.apple.developer.carplay-video not found and could not be included in
  profile"*. The check is on the **device** (the phone runs CarPlay), so a
  simulator build cannot help: the CarPlay Simulator in Xcode 27 hosts
  **physical devices only** (its *Sessions* menu lists the iPhone and nothing
  else, even with a simulator booted). A profile is signed by Apple and cannot
  be forged. So the flip — *Identifiers → XC com rushabh cartvv → Capabilities →
  CarPlay Video on → Save* — was the whole job, and it is **done** (2026-11-03):
  the profile Apple minted afterwards carries `carplay-audio` **and**
  `carplay-video`, and the device build signs with both. It needs the **account
  holder** to press the buttons in the portal; the profile itself comes from
  Xcode when an account is signed in (see the next bullet).
- **"No Accounts" comes from `-allowProvisioningUpdates`, not from signing.**
  Automatic signing works **offline**: with a matching profile in
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, `xcodebuild … build`
  signs the app with it and never contacts the portal — measured on the device
  build on a machine with no Apple account in Xcode. `-allowProvisioningUpdates`
  is what asks the portal for a profile, and that is what fails with "No
  Accounts". So the fix for a missing entitlement is a **downloaded** profile,
  not a signed-in account.
- **An unsigned app has no `application-identifier`, so the Keychain refuses
  every write with `-34018`** (`errSecMissingEntitlement`) — the credentials of
  a source cannot be stored at all. `CODE_SIGNING_ALLOWED=NO` still builds and
  installs, but the Keychain is dead in that build. (This is why the ad-hoc
  simulator build needed `CODE_SIGN_IDENTITY="-"`: it is the only way an
  unsigned-looking build still gets an `application-identifier`.)
- **The app's profile does not cover the broadcast extension.** The extension's
  bundle id is `com.rushabh.cartvv.ScreenRelay` and the profile's app id is
  `com.rushabh.cartvv` — Xcode insists on an **exact** match (*"has app ID …,
  which does not match the bundle ID …"*), so a profile for the app cannot sign
  the extension. Automatic signing gives the extension the **wildcard** profile
  (`47T499AR2T.*`) on its own, so only the app needs the new profile.
- **`CODE_SIGN_STYLE=Manual` refuses Xcode-managed profiles.** A profile
  Xcode created carries `IsXcodeManaged`, and manual signing rejects it
  (*"is Xcode managed, but signing settings require a manually managed
  profile"*). A profile **downloaded from the portal** is accepted. So manual
  signing is a way to *force* a specific profile — not a way around a missing
  one.
- **Two profiles for one app id leave Xcode to guess.** The old audio profile
  and the new video profile both name `com.rushabh.cartvv`, and the wrong one
  signs the build (the app then fails to install with `0xe8008015` — a valid
  provisioning profile for this executable was not found). The profile that is
  replaced is **moved aside** (its file name loses the `.mobileprovision`
  extension, so Xcode does not see it), never deleted.
- **The CarPlay Simulator's session dies with the USB connection.** Its
  windows vanish (the *Window* menu still lists them, the AX window list is
  empty) and the app has to be restarted; it can also fail on its own
  (*AirPlay Session Failed … Reason: -10879*) and take the CarPlay scene
  down with it. Watch for `DRIVEPLAY CarPlay scene connected` /
  `… disconnected` in the app console — a scene that connects and disconnects
  in seconds means the simulator link, not the app.
- **Never click the car display blind.** The user is usually using the Mac, and
  a click that lands in the wrong window goes into their chat or their
  browser. Verify with `NSWorkspace.frontmostApplication` that *CarPlay
  Simulator* is frontmost **immediately before** posting the `CGEvent`, and
  abort instead of clicking (`/tmp/cpclick.js` does raise → verify → click →
  capture).

- **The CarPlay entitlements are Apple-granted.** `CarTV.<category>.entitlements`
  grants one `com.apple.developer.carplay-*` key — the video key is `carplay-video`, **not**
  `carplay`, and it needs **iOS 27**. It cannot be self-enabled: the *device* build stops
  signing until the provisioning profile carries it, so ask before changing it. The
  Simulator build is unaffected.
- **Xcode cannot add the CarPlay Video capability to an app id.** Measured on the device
  build with `-allowProvisioningUpdates`: Xcode reaches the portal (it mints profiles) but
  refuses to create an app id that carries `com.apple.developer.carplay-video` — it falls
  back to the wildcard profile (`XC Wildcard`, `application-identifier 47T499AR2T.*`, no
  CarPlay keys). Two brand-new bundle ids behaved the same. The flip has to be done in
  developer.apple.com (Identifiers → App ID → Capabilities → CarPlay Video on, CarPlay
  Audio off — both at once is not supported).
- **CarPlay asks the app for video only when the app is entitled to it.** A row with
  `CPPlaybackPresentation.video` is refused without the video entitlement —
  *"cannot prepare playback: presentation is video but app does not have the video
  entitlement"* (logged by `CarPlayTemplateUIHost(CarPlaySupport)`), and no picture
  appears on the car. `.video` means *"present video if available, otherwise show now
  playing"*, so the safe request is `.audio` for a build without the entitlement.
  The entitlement lives on the app id, so **the build knows**: `CARPLAY_CATEGORY` picks
  the entitlements file *and* the `CarPlayCategory` key in the Info.plist, and the app
  reads that key.
- **`CODE_SIGN_ENTITLEMENTS` accepts a build setting.** `CarTV/Resources/CarTV.$(CARPLAY_CATEGORY).entitlements`
  expands, so one setting picks the file — and `$(VAR)` in an Info.plist value expands
  too (`INFOPLIST_EXPAND_BUILD_SETTINGS` is on by default). Check what landed with
  `plutil -p build/.../CarTV.app/Info.plist`.
- **ReplayKit cannot record the screen while CarPlay is connected.**
  `RPRecordingErrorCarPlay` (-5813) — *"Failed to start recording due to carplay being
  active"* — is what `RPScreenRecorder.startCapture` returns with the car attached. The
  capture behind a CarPlay row can therefore never work; a **broadcast** (the
  `com.apple.broadcast-services-upload` extension, the WhatsApp-style screen share) is
  the mechanism that does. A capture that delivers no frame must not fall back to the
  demo picture here: the car would show a fake animation.

- **The Simulator can carry the CarPlay video entitlement; the device cannot.**
  The entitlement lives in the app's Mach-O (`__TEXT,__entitlements`) and the
  Simulator never checks it against a profile, so a build with
  `CARPLAY_CATEGORY=video` makes the CarPlay Simulator accept the video
  surface. The **device** build is the opposite: without the Apple-granted
  capability it does not sign at all, which is why the default stays "audio".
  `scripts/carplay_simulator.sh` builds, installs and prints both facts
  (the entitlements file and the `CarPlayCategory` in the built Info.plist).

- **The CarPlay Simulator has no screen to record and no broadcast to start.**
  `RPScreenRecorder` delivers no frame there and a broadcast extension cannot
  be started, so the car's row waits for something that never arrives. The row
  therefore starts the demo picture on the Simulator
  (`ScreenShareService.startForTheCar`) — the same capture → encode → serve →
  play chain. On a real phone the row waits for the broadcast: a fake picture
  on a real car is worse than nothing, so the fallback is
  `#if targetEnvironment(simulator)`, never a runtime guess. **What the demo
  cannot do in Xcode 27 is reach a car:** the Simulator hosts no CarPlay
  session (see the bullet above), so the picture is only watchable over the
  local network (`http://<host>:<port>/<token>/live.m3u8`).

- **`AVAssetWriter.finishWriting` throws when the writer never started.** The
  encoder starts with the first frame, so a capture that delivers none leaves
  the writer in status `.unknown` — finishing it raises
  `NSInternalInconsistencyException` and **terminates the app**. That was on
  the normal path: the Simulator delivers no frame, and a phone with CarPlay
  connected is refused with -5813, so tapping the car's row could kill the
  app. Guard on `writer.status == .writing`. It is a race, too — the Simulator
  sometimes delivers a single frame before it stops, which is why the crash
  showed up in one test run and not the next.

- **The whole ReplayKit broadcast family is "no longer supported" in iOS 27 —
  except the picker, which is still there.** Measured in the iOS 27 SDK
  (device *and* simulator): `RPBroadcastSampleHandler` (the upload extension's
  base class), `RPBroadcastActivityViewController` and `RPBroadcastController`
  are deprecated with *"No longer supported"*, but
  `RPSystemBroadcastPickerView` is only deprecated with *"Use ScreenCaptureKit
  SCContentSharingPicker instead"* (`ios(12.0, 27.0)`) — **it is still in the
  SDK and still usable**, and the app uses it to put the system broadcast list
  in front of the user. Its deprecation version (27.0) is above the app's
  deployment target (18.0), so it compiles **without a deprecation warning**.
  `RPScreenRecorder` is deprecated too, yet it still runs (it is what returns
  -5813), so a deprecation message is not the same as a removed API — but the
  broadcast upload extension may well stop being launched on iOS 27.

- **ScreenCaptureKit cannot replace the broadcast on iOS.** In the iOS 27 SDK
  `SCShareableContent` is `API_UNAVAILABLE(ios, visionos, tvos)` — an iOS app
  cannot enumerate another app's windows, displays or applications — and the
  only iOS picker is `presentPickerForCurrentApplication`, which captures
  **the app's own screen**. So ScreenCaptureKit on iOS 27 is app-only capture
  and cannot mirror another app to the car; the broadcast upload extension is
  the only mechanism that can. ScreenCaptureKit is also **device-only**: the
  iPhoneSimulator SDK has no `ScreenCaptureKit.framework` at all.

- **The relay only listens.** `ScreenShareService.startRelay()` must never stop
  the share that is running: the broadcast replaces it when the extension
  announces its stream (`playRelay`), not when the relay starts. The relay has
  to be listening *before* the user picks the broadcast in the system list, so
  it is started as soon as the share card appears — which only works because
  starting it no longer disturbs the running share.

- **One CarPlay category per app — but audio and video can be combined.** Apple grants one
  category per app ("Multiple categories cannot be combined in a single app" — CarPlay
  Developer Guide, October 2026), and each category has its own entitlement key. The
  categories are listed in the guide's appendix — `carplay-audio`,
  `carplay-communication`, `carplay-driving-task`, `carplay-charging`, `carplay-fueling`,
  `carplay-maps`, `carplay-parking`, `carplay-public-safety`, `carplay-quick-ordering`,
  `carplay-video` (iOS 27), `carplay-voice-based-conversation`. Each category may only use
  the templates in the guide's matrix (page 15) — an unsupported template throws at runtime.
  **The exception is video:** Apple's own guidance ("Rev up your CarPlay app", WWDC26) is to
  include **both** `carplay-audio` and `carplay-video` when the content suits both — "with
  both entitlements your app can always appear in CarPlay", because an app with only the
  video entitlement does not appear on the home screen of a car without "video in car".
  The profile Apple minted for this app id carries **both** keys, and the device build
  signs with both. The real rule is not "one key" but **"ask for exactly what the profile
  carries"** — a key the profile does not carry stops the build.
- **The car's display is an AirPlay destination.** A CarPlay video app "needs to support
  AirPlay video streaming" ("Rev up your CarPlay app", WWDC26): the picture travels the
  AirPlay route, so the `AVPlayer` needs `allowsExternalPlayback = true`. Without it the
  video plays on the phone and the car's display stays black — and nothing errors.
  `PlaybackManager.play(channel:)` had it only on the screen-share path, so every channel
  played for the car stayed on the phone.
- **The audio session's options belong to its category — and the category change
  fails as a whole.** `.allowAirPlay` is *"only valid with `AVAudioSessionCategory
  PlayAndRecord`"*, and `.allowBluetooth`/`.allowBluetoothA2DP` are rejected with
  `.playback` as well. The player set up its session as `.playback` with all three, the
  system refused the whole call (**OSStatus -50**) and `setActive` was never reached — so
  the session was **never activated** and the AirPlay route to the car was never
  offered. Measured on the device: `.playback` accepts **no options at all**.
- **An `AVAudioEngine` keeps the input format of the session it was born in.** The
  player holds the session as `.playback` — a category with **no input route** — so an
  engine created then reports `channels=2 rate=0.0`, and the recorder dies with
  *"IsFormatSampleRateAndChannelCountValid"* / *"com.apple.coreaudio.avfaudio error
  1852797029"* (`PerformCommand(*ioNode, kAUStartIO)`). The engine has to be created
  **after** the session is configured for recording, and the player's session has to be
  handed back when the recording ends.
- **Xcode mints the profile itself when an account is signed in.** With the Apple account
  signed in on the build machine, `xcodebuild … -allowProvisioningUpdates` asks the portal
  for the profile and installs it — no manual download, no manual steps in the portal.
  The portal's app id has to carry the capability first; the profile then carries the
  entitlement (measured: the profile for `com.rushabh.cartvv` carries **both**
  `carplay-audio` and `carplay-video`). Without an account the same build fails with
  "No Accounts" — that is the only difference.
- **The CarPlay request comes from the Apple account, not from the code.**
  `docs/carplay-video-request.md` is the package the account admin sends: the form is behind
  the Apple ID sign-in and the CarPlay Entitlement Addendum has to be accepted by the Account
  Holder. `scripts/carplay_grant.sh check` says whether the local profile already carries the
  entitlement; `scripts/carplay_grant.sh grant` fetches a new one once Apple has granted it.
- **The scheme has to be defined at the project level.** A scheme under
  `targets.<target>.schemes` is not written to disk, so `xcodegen generate` produces no
  `.xcscheme` and Xcode silently falls back to an auto-created one — which loses the test
  target and the StoreKit configuration. The shared scheme lives in the top-level `schemes:`
  block of `project.yml` (`CarTV.xcodeproj/xcshareddata/xcschemes/CarTV.xcscheme`).
- **The local StoreKit configuration is `Configuration/DrivePlay.storekit`**, attached to the
  scheme's **Run** action (`storeKitConfiguration:` in `project.yml`). Only the Run action
  supports it — the test action has no such setting, so `xcodebuild test` runs against the
  real store. If the scheme ever shows no configuration, pick the file once in
  *Scheme ▸ Edit Scheme ▸ Run ▸ Options* and Xcode writes the path into the scheme itself.

## Gotchas from the second review (2026-11-03)

- **`AVMediaSelectionGroup` only exists for assets with *alternate renditions*.** A
  plain file — a WAV, an MP4 with one audio track — has **no** audible media selection
  group, and neither does an `AVMutableComposition`: its tracks are tracks, not
  options. So `item.select(_:in:)` cannot be exercised in a unit test without a server
  that serves HLS with alternate audio renditions. Measured on macOS:
  `AVURLAsset.loadMediaSelectionGroup(for: .audible)` → `nil`, and
  `AVMutableComposition.mediaSelectionGroup(forMediaCharacteristic: .audible)` → `nil`.
  The track picker is therefore pinned by a **contract** test (the selection is
  read-only from the outside; an unknown track changes nothing) and by the
  `public private(set)` on `selectedAudioTrack` / `selectedSubtitleTrack` — the
  compiler, not the test, is what stops a picker from writing the name itself.
- **`AVMediaSelectionGroup` has no `select(_:in:)`.** The API is
  `AVPlayerItem.select(_:in:)` — the group is the *second* argument. `group.select(option,
  in: item)` does not compile.
- **A `guard` in `didStartElement:` does not stop `foundCharacters:`.** XMLParser
  delivers the attributes and the text separately, so a guard that skips a second
  `<res>` element still lets its text be appended to the first one's URL. Both the
  element callback **and** the text callback have to refuse it.
- **`UIDevice.current.orientation` only changes while the device is *generating* the
  notifications.** `beginGeneratingDeviceOrientationNotifications()` has to be called
  (and `endGeneratingDeviceOrientationNotifications()` when the view goes away) — without
  it the rotate handler never runs and never says so.
- **A test that touches the user's own data has to be pointed at a temporary
  directory.** `LocalMediaService` writes the vault index into `Documents/ImportedVideos`
  — a device test that imports a file puts a junk entry into the user's vault. The
  service takes the directory it works in (`LocalMediaService(storageDirectory:)`) so the
  test never touches the real one.
- **`CPListTemplate.maximumItemCount` counts the items across *all* sections**, not per
  section — the budget has to be counted before a section is added, not per section.

## Gotchas from the third pass (2026-11-03, the device)

- **A token that rides in a query has to be taken out of *every* URL field, not
  only the stream URL.** The artwork carries the same token — the image loader
  cannot send a header, so it rides in the query — and only `streamURL` was
  redacted before the file was written. The library file (`saved_channels.json`)
  and the watch history therefore held the account's token in the clear.
- **The copy in memory keeps the real URL; the copy on disk is the redacted
  one.** The watch history redacted the URL *into* the item it kept in memory,
  so the "watch again" row played `…?api_key=__dp_token__` until the app was
  restarted. Redact on the way to the disk, restore on the way back.
- **The orientation generation belongs to the device, not to a monitor.**
  `UIDevice.isGeneratingDeviceOrientationNotifications` is a property of the
  device: a second monitor that called `endGeneratingDeviceOrientationNotifications()`
  switched off what the first one had started, and the rotate handler went
  quiet. A monitor may only stop what it started.
- **A test that indexes rows by position takes the whole test runner with it.**
  An index-out-of-range in a test **kills the test host** — on the device that
  is 12 other tests that never finish. Look the row up by its text and fail
  the assertion instead.
- **A test that skips when a permission is missing reports "0 failures".**
  `VoiceSearchTests` skips without the microphone, so the suite was green
  while the app's own path — the one the user actually touches — failed. The
  skip is honest, but the suite then says **nothing** about the feature. The
  permission is granted on the phone by tapping the mic once; after that the
  test runs for real, and it is the only thing that caught the bug below.

## Gotchas from the fourth pass (2026-11-03, the microphone)

- **A connected car takes the phone's microphone with the audio route.**
  While the CarPlay session is up the phone's route is the car's: the output
  is `CarAudio` and so is the **input** — and the car's input cannot record,
  so the recorder dies with *"PerformCommand(*ioNode, kAUStartIO)"* →
  *"com.apple.coreaudio.avfaudio error 1852797029"*. The phone's own
  microphone has to be asked for by name:
  `session.setPreferredInput(builtIn)` on the `builtInMic` port out of
  `session.availableInputs`. The same test passed minutes earlier — with the
  car **not** attached — so "it is flaky" was the wrong conclusion; print the
  route (`session.currentRoute.inputs`) and the difference is right there.
- **The audio route arrives after the session does — wait for it.**
  `setActive(false)` returns before the session has really gone, so
  `setCategory(.record)` often lands on a session that is **still active**.
  iOS then tears the old route down and builds the microphone's route in the
  background, and an `AVAudioEngine` that starts in that window finds **no
  input**. Wait for the route instead: `session.currentRoute.inputs` must
  carry the microphone before the engine starts.
- **The warning tells you which way the race went.**
  `AVAudioSession_iOS.mm:978` is the generic "called on the main thread"
  warning; `SessionCore.mm:631` is the one that says *"while the audio session
  is active"*. The failing run showed the **second** warning on the category
  change and the passing run the first. Print the session's state (category,
  mode, rate, route in and out, the inputs on offer) and the engine's formats
  before believing a microphone failure — *"1852797029"* says nothing.
- **A car can lock the phone's microphone for *every* app.** Measured on the
  device with the CarPlay simulator attached: `engine.start()` fails with
  *"com.apple.coreaudio.avfaudio error 2003329396"* (`'what'` — the input
  refuses to open), and `setActive(true)` fails with `'!pri'` (*"priority"* —
  another session owns the audio). It is **not** the app's code: the same
  engine fails with **no app code at all** (plain `setCategory(.record)` +
  `setActive(true)` + `engine.start()`), and it fails in every category
  (`.record`, `.playAndRecord`, with and without `.allowBluetooth`). The
  device's session server shows who holds the route — another app's session
  (`corespeechd`, another app's `PickedRouteForSession` on `CarPlay`).
  The microphone comes back when the holder lets go, so the test has to
  **probe** it (`VoiceSearchTests.canOpenTheMicrophone`) and skip with that
  reason — a skip that says *why* is honest; a test that fails on the
  system's behaviour is not the app's bug.
- **A failed microphone must still give the player its session back.**
  The voice search borrows the audio session (`.record`); if the microphone
  could not be opened the session was left as `.record` and the video lost
  its sound. `VoiceSearchManager.startRecording` now restores the player's
  session on **every** path out.

## Gotchas from the fifth pass (2026-11-03, the car's Home tab)

- **The CarPlay session can die without the app crashing.** The Home tab was
  built from every one of the playlist's 184 categories, and every category is
  a row of 8 cards: ~400 pictures the phone had to draw at the car's scale.
  The build alone took ~7 s, and every logo that arrived rebuilt the whole
  template again, so the car was sent the entire catalogue hundreds of times
  over. The CarPlay host's own log says it out loud —
  `CarPlayTemplateUIHost(FrontBoardServices)[pid] [scheduledTime] Updated
  resource consumption: 5.842s (58.97%)` — and the scene is torn down when it
  reaches 100 %. **Watch that line**, not the app's crash log: there is no
  crash log, because the app never crashed.
- **A logo that arrives must patch the picture, not rebuild the screen.**
  The rebuild-per-logo is what killed the session. CarPlay has a documented
  way to update a picture in place, and it is on the item itself:
  `CPListItem.setImage:`, `CPListImageRowItem.elements` (a settable array of
  `CPListImageRowItemElement`, of which `CPListImageRowItemCardElement` is
  the card) and `CPListSection.headerImage`. The deprecated `updateImages:`
  is gone in iOS 26 — `elements` replaced it.
- **`CPListImageRowItem.init(text:cardElements:)` takes
  `[CPListImageRowItemCardElement]`, but the `elements` property is
  `[CPListImageRowItemElement]`.** The card is the subclass, so keep the
  cards in a `[CPListImageRowItemCardElement]` and assign
  `row.elements = cards.map { $0 as CPListImageRowItemElement }` when a logo
  lands.
- **A card is a big picture.** `CPListImageRowItemCardElement.maximumImageSize`
  is much larger than `CPListItem.maximumImageSize`, and the tiles are cached
  at the car's scale — so the tile cache has to be bigger than the logo cache
  (32 MB → 128 MB) or every rebuild redraws every card.
- **A section's header image belongs to the section, not to a row.** A
  category's picture is the picture of its first channel, and it is patched
  through `CPListSection.headerImage` when that logo arrives.

## Gotchas from the sixth pass (2026-11-03, the encoder and the green)

- **The encoder needs an IOSurface-backed pixel buffer — the Simulator does not
  care.** The app's own frames were created with `CVPixelBufferCreate(…, nil,
  …)`; the **device's** VideoToolbox then refused every one of them —
  `FigSampleBufferSerialization err=-19642`, logged by the app as *"a frame
  could not be appended"* — so the screen share produced **no fragment at all**
  on a real phone. The Simulator's encoder takes a plain buffer, so the whole
  chain looked whole there. The fix is one attribute:
  `[kCVPixelBufferIOSurfacePropertiesKey as String: [:]]`. The test helper in
  `ScreenShareTests` had it all along — that is why AC29 passed and AC31/32/34/43
  failed: same encoder, different buffer.
- **A card's tint paints the frame *and* the text on it.** `CPListImageRowItemCardElement`
  takes a `tintColor` (nullable): the system paints the card's frame and the
  subtitle in it. A tint of ours therefore put a green frame around **every
  card of every category** — pass `nil` and let the car paint its own cards.
  The same goes for the tab icons: `UIImage(systemName:)` is a template, and
  `.withTintColor(…, renderingMode: .alwaysOriginal)` takes that away from the
  system.
- **A CDN with a per-IP quota is the norm, not the exception.** A third of the
  playlist's logos live on imgur, which answers **429** when more than about a
  hundred pictures are asked for in a short while — and the car asks for a whole
  category at once (453 channels). Measured: 52/451 refused at concurrency 8,
  16–19/120 at concurrency 2–6; with a **0.25 s gap** between requests, 194/200
  came back. So the pictures are asked for **one after another** (a gate, not a
  queue), a refused one is asked for again (3 attempts), and a card is drawn
  from **the logo that arrived** — never from a cache lookup, because the logo
  cache is bounded and can come back empty for a picture it was just handed.

## Gotchas from the seventh pass (2026-11-03, the picture and the car's browser)

- **The AirPlay route is looked at only when the picture is offered.** The
  system's own log shows the evaluation: `airplayRoute_updateRouteInformation
  … Selected endpoint from routing context … Local Playback = 1`. It happens
  when the playback item is created, and it is not repeated by itself — so a
  picture offered **before** the car's video endpoint exists finds no endpoint
  and stays on the phone, and nothing else makes the system look again.
  `replaceCurrentItem(with:)` — even with the *same* item — is what makes the
  system build a new player and look at the route again (the app's
  `castToPhone()` already relied on it).
- **The car's video endpoint arrives *after* the CarPlay scene connects.**
  Measured on the device: the endpoint "CarPlay (ScreenMain)" was registered
  two minutes after the first tap, and no route evaluation followed it — so
  the picture has to be offered **again and again** for a while, not once.
- **No public API picks an AirPlay route.** `AVRoutePickerView` is the only
  control the system gives; `CPSessionConfiguration.supportsVideoPlayback`
  (iOS 26.4+) exists but the app cannot get an instance of it — there is no
  accessor on `CPInterfaceController`, on the scene, or on UIKit. So the app
  can only *offer* the picture, and the route the user picks is the system's
  own. With a car connected the button therefore hands the picture over
  directly instead of showing the list, which is the only thing the user does
  not want to see.
- **A `CPSearchTemplate` can be a tab, and it has no `updateSections`.** ←
  **WRONG — corrected 2026-11-03.** The **compiler** takes any `CPTemplate`,
  but the **runtime does not**: `-[CPTabBarTemplate validateTemplates:]`
  **raises an `NSException`** when one of the templates is a search template,
  and the app dies with **SIGABRT** at *every* CarPlay scene connect. The
  device's crash reports say so plainly (`CarTV-2026-11-03-173042.ips` and
  five more the same evening):

  ```
  objc_exception_throw → +[NSException raise:format:] → -[CPTabBarTemplate validateTemplates:]
  ```

  The tab bar takes **lists only**, and the address bar is **pushed onto the
  stack** (`pushTemplate`) instead of being a tab. The rule is pinned in the
  compiler, not in a comment: `CarPlaySceneDelegate.makeTabBar(_ templates:
  [CPListTemplate])` — a search template cannot be passed to it at all.
  A search template's results still only exist through the delegate's
  completion handler, so the app remembers what each result stands for (the
  item's own `ObjectIdentifier`), and the search template's delegate is
  **`weak`** — the app has to hold it.
- **A tile that is drawn is a tile that is paid for.** The browser draws a row
  of site tiles on **every keystroke**, at the car's scale — so the tiles are
  cached like the channel tiles are (`CarPlayArtwork.siteTile`).

## Gotchas from the eighth pass (2026-11-03, the picture's home and the car's speed)

- **The picture's home belongs to the system, not to the app.** The hand-off
  hid the phone's picture the moment it was asked for, and the car only takes
  the picture when the **system** says so (`isExternalPlaybackActive`). A car
  whose video endpoint was not ready yet therefore left the video on **neither**
  screen — the user's *"sometimes only in the car, sometimes only on the
  phone"*. The phone keeps drawing the picture until the system reports it on
  the car; the app must never hide its own picture on the strength of its own
  request. And the flag has **one** writer: `@Published public private(set)`
  plus a single entry point (`systemSaysPictureIsOnCar(_:)`), because a flag
  with two writers makes the banner flicker.
- **A ladder that is not cancelled yanks the picture back.** The re-offer
  ladder (the car's endpoint appears minutes later) was never stopped, so a
  picture the user had taken back to the phone jumped back to the car a few
  seconds later, on its own. Every hand-off and every picture taken back gets
  a new **generation**, and the ladder checks it before every offer.
- **The player's flags must be set before the item is attached.** The system
  looks at the AirPlay route when the item arrives. `allowsExternalPlayback`
  set *after* `replaceCurrentItem` leaves the picture local for good — the
  route was already evaluated.
- **The now-playing artwork must be drawn once.** The now-playing info is
  refreshed four times a second while a video plays, and the artwork was
  **drawn** every time: a 512×512 gradient, a symbol and three lines of text
  on the main thread, four times a second. That is what made the phone
  stutter. The picture is drawn once per channel and kept, and the info is
  only handed over when something in it changed (the system counts the
  seconds itself once the rate is known).
- **A per-IP quota belongs to the host.** The 0.2 s gap between logo requests
  exists because of one CDN that answers *429* — and the quota is **that
  server's**, not the app's. One global gate made the car wait for the *sum*
  of every server's gaps (eight servers: 1.6 s instead of 18 ms). The gate is
  per host now; one host still waits its turn.
- **The car is told once per batch.** A logo that arrives patches the card
  that shows it, but the **row** is handed to the car again — and a row
  carries every card in it. Eight pictures meant eight reloads of the same
  row. The patches are collected and handed over in one batch
  (`CarPlayCardPatcher`).
- **Measure before blaming the build.** The Home tab is built in **48 ms** —
  it was never the bottleneck. The waits were the pictures (one global gate)
  and the re-sends to the car (one per picture).

## Gotchas from the ninth pass (2026-11-04, the minimised player)

- **The iOS 26+ `TabView` swallows `safeAreaInset(edge: .bottom)` whole.** The
  tab view is UIKit's own (`UIKitAdaptableTabView`) and the root
  `_UIHostingView<MainTabView>` ends up with **one** subview — the platform
  view host. A `safeAreaInset` on the bottom edge therefore renders
  **nothing**: the minimised player was never on the screen, and the state
  was right all the time. A bar that has to sit **above** the tab bar is an
  **overlay** in the `ZStack` — the same shape the docked player already used
  — and the tab bar's height is **measured** from the live window
  (`MainTabView.tabBarHeightInWindow()`, 83 pt on an iPhone 13 with a home
  indicator) rather than guessed: the bar floats on iOS 26+ and its height
  differs from phone to phone.
- **The tab bar is a `_UIBottomTabBarGroupView` with a floating pill inside
  it.** `UITabBar.bounds.height` (83) is the whole group, the pill
  (`_UITabBarItemPlatterView`, 62) floats inside it, and the home indicator's
  safe area is **below** the pill. Padding by the group's height puts the bar
  right above the pill; padding by the safe area alone puts it behind it.
- **`SFSpeechRecognizer` calls back on its own queue.** The result handler of
  `recognitionTask(with:)` is not on the main thread, so publishing the
  transcript from it is *"Publishing changes from background threads are not
  allowed"* — a crash with **no crash report** (it is a fatal error, not a
  signal). The transcript crosses to the main actor first
  (`VoiceSearchManager.handleTranscript`, a `nonisolated` seam that hops
  through `Task { @MainActor in }`); the same goes for `onResult` and for
  `stopRecording()`. The same rule is in the ReplayKit capture handler, which
  hands its frames to the main thread before they reach the display layer.
- **A portrait video needs `.resizeAspectFill`, a landscape one must not have
  it.** Every surface used `.resizeAspect`, so a 9:16 phone-shot video stood
  in the middle of the car's landscape screen with a black bar on **both**
  sides. `VideoGravityPolicy.gravity(for:)` reads the item's own
  `presentationSize` (the size **with** the preferred transform) and fills the
  frame only when the picture is taller than it is wide — a landscape channel
  keeps `.resizeAspect`, because a logo at the edge of the picture must not be
  cropped away.

## Gotchas from the tenth pass (2026-11-04, the ad blocker and Plex)

- **A content blocker's `url-filter` matches the **whole URL**, the query string
  included.** The pattern is a regex searched **anywhere** in the URL, so a rule
  for `googletagmanager.com` also stopped
  `https://www.google.com/ccm/collect?scrsrc=www.googletagmanager.com` — the
  page's *own* request, killed by a host it only **mentioned**. Anchor the
  filter to the **host of the request** instead:
  `^https?://([^/]+\.)?<host>(:[0-9]+)?/` — the host has to be the one that is
  *called*, and nothing after the host can ever match.
- **`if-domain` is the **top document's** host, matched **exactly** — not the
  host of the request, and not "the host or a host under it".** Measured with a
  real `WKWebView`: a rule with `if-domain: ["127.0.0.1"]` never stopped an
  image loaded from `127.0.0.1` while the page was on `localhost`, and a rule
  with `if-domain: ["0.0.1"]` never matched the page on `127.0.0.1`. So a
  block rule that names an ad host with `if-domain` **never stops that ad** —
  it only fires on a page that *is* the ad host, where it then blocks
  everything. `if-domain` is the right tool for an **exemption** ("leave this
  site alone") and the wrong tool for a block. `unless-domain` reads the same
  host the same way.
- **A tag manager is not an ad host.** `googletagmanager.com` is the pipe a
  site's **own** configuration travels through — SonyLIV's sign-in page took its
  login-and-tray setup from there (measured: the rules took 33 of the page's 93
  resources away, and the tag manager was one of them), so blocking it breaks
  the page while the ads it fires at stay blocked **on their own**. A block list
  that names a tag manager is naming the site's own plumbing.
- **The CSS rule of a blocker has to be `load-type: ["first-party"]`.** A
  captcha badge, a payment form and a consent banner all live in a
  **third-party frame**, and a rule that matches every frame can hide the thing
  the user came for. The captcha and identity providers are excepted with
  `unless-domain` as well — with the `www.` twin, because the match is exact.
- **WebKit knows exactly two load types: `"first-party"` and `"third-party"`.**
  `"top-frame"`, `"child-frame"`, `"main-frame"`, `"top-level"` and
  `"topFrame"` are all refused (*"Rule list compilation failed: Invalid string
  in the trigger flags array"*) — and **one bad rule fails the compilation of
  the WHOLE list**, so the blocker is then dead and only the log says so.
  `"first-party"` is the page itself; `"third-party"` is everything else.
- **`if-top-url` needs a **literal scheme** — `*://site/*` does not compile.**
  Measured: `http://site/*`, `https://*.site/*` and `site/*` compile; every
  pattern that **starts** with `*` fails with *"Internal error in YARR"*.
  The exemption uses `if-domain` instead, so the question does not arise.
- **`ignore-previous-rules` has to come **last**, and it cancels the rules
  before it.** That is how a site the user let through is left alone — the
  exemption is a rule, not a flag.
- **A site name has to be a host name.** The exemption ends up in a rule as a
  host, and a host with a glob character in it matches **other** hosts too.
  `URL(string: "https://*.evil.com/x")` parses and its host is `*.evil.com`,
  and `https://*/` parses too: without a check on the site name, opening
  such a URL in the app's browser would let **every** site through. The site
  name is accepted only when it is letters, digits, dashes and dots.
- **The compiled rule list is cached under its identifier.** WebKit keeps it, and
  the app asks for it *by name* before it compiles anything — so a list compiled
  from the **old** rules is found and used, and the new rules are **never
  compiled**. The identifier (`DrivePlayAdBlockerRulesV8`) has to change with
  the rules.
- **Compile the real list in a test.** The rule list is one thing to WebKit —
  a single value it does not know kills every rule — and a unit test that
  *simulates* the matching cannot see that. `AdBlockerTests` hands the list
  the app really produces to `WKContentRuleListStore` and fails when WebKit
  refuses it.
- **Compiling again under the *same* identifier does replace the rules.**
  Measured: rules A (block `localhost`) stopped a page from loading; rules B
  (block `127.0.0.1`) compiled under the **same** identifier let it through
  again. So a recompile for a *changed* rule set (an exemption) does not need
  a new name — only a change of the rules *themselves* does.
- **`WKContentRuleListStore.compileContentRuleList` calls back on the main
  queue.** Waiting for it with a semaphore on the main thread **deadlocks**;
  the run loop has to keep turning until the list arrives.
- **`WKUserContentController` cannot be asked what rule lists it holds** —
  `contentRuleLists` is not public API. Only `add`, `remove` and
  `removeAllContentRuleLists` exist, so a test has to assert on the *decision*
  (a rule list to hand over, or none) and not on the controller.
- **A `WKWebViewConfiguration` is copied when the web view is made, but its
  `userContentController` is a shared reference** — a rule list added later
  reaches the web view that is already open, for the **next** load. The page
  has to be reloaded for a change to be seen — and the rules are compiled in
  the **background**, so the reload has to happen **after** the compile, not
  before it. A reload fired at the moment the switch is flipped loads the
  page with the *old* rules, and the switch looks like it did nothing.
- **plex.tv answers `provides` both as a string and as a list.** A decoder
  that knows one of them reads **nothing**, and the server looks like it is not
  there.
- **`(try? JSONDecoder().decode(...)) ?? []` turns every error into "no
  servers".** A decode failure and an account without a server are two
  different problems; the status is read **before** the body, because a
  refused account (401) answers with a JSON **object** and not with a list.
- **A server that is not on the network the phone is on needs its relay
  address** — `GET /api/v2/resources?includeHttps=1&includeRelay=1`. Without
  `includeRelay=1` the answer holds a server with **no usable address at
  all**, and the account looks empty.

## Gotchas from the eleventh pass (2026-11-04, the car's picture, the page and the compass)

- **The CarPlay Simulator shows the *template* scene, not the app's own car
  UI.** `ExternalDisplaySceneDelegate` → `InCarAutomotiveController` is a
  plain `UIViewController` for a real second screen, and the **CarPlay
  Simulator renders `CarPlaySceneDelegate`'s templates** — the app grid, the
  tab bar, the lists. So the address bar of the car's browser is a
  `CPSearchTemplate` pushed onto the stack, and the custom browser, its
  toolbar and its address bar are a **different** code path that the simulator
  never shows. Verify which scene a window shows with a window list
  (`CGWindowListCopyWindowInfo`) and a capture of that window id, not by
  reading the code.
- **The re-offer ladder has to run for *every* car-wanted play.** The guard
  `if isCarConnected && presentation != .hidden` skipped the ladder for
  exactly the play the **car** asked for (the car plays with
  `presentation: .hidden`) — so the picture was offered once, at the moment
  the row was tapped, and the car's endpoint (up to two minutes later) never
  saw it. The ladder also has to **repeat**: a fixed list of offers ends long
  before the endpoint is there.
- **The first gap of the ladder must be long enough for the video to start.**
  An offer rebuilds the player and drops the buffer, so an offer that lands
  on the start is the stutter the user feels as "laggy". The gaps grow
  (2.5 s, 2.5 s, 4 s, 7 s, 12 s, 20 s, 30 s) instead of starting at 1 s.
- **A page that reaches the car goes through the phone's screen share — and
  the share has to be handed off too.** `playScreenShare` never called
  `handOffToCar`, so even a working broadcast played on the phone. iOS always
  asks the **user** to start a share (`RPSystemBroadcastPickerView`), so the
  app has to put that button in front of them when the car asks for a page —
  the car's screen is not a touch screen.
- **A search template's list must not be built again for every keystroke.**
  `searchTemplate(_:updatedSearchText:completionHandler:)` is called on
  **every character**, and every row carries a picture at the car's scale —
  so the rows are built **once** and filtered afterwards. The same rule as
  the Home tab's cards: a picture that is drawn is a picture that is paid
  for, and the car tears the scene down when the resource consumption
  reaches a hundred per cent.
- **A dead web process must not be reloaded in a loop.**
  `webViewWebContentProcessDidTerminate` reloaded the page unconditionally:
  the page that killed the process was loaded again, killed it again, and the
  app was taken down with it (the watchdog kills an app that stops
  answering — the symptom is a redirect to the home screen, with **no crash
  report**). One reload, then the catalogue takes the screen back. The
  phone's browser tab had no handler at all, so a dead page stayed dead.
- **The compass rose turns *against* the heading, and the needle is fixed.**
  A car heading east has north on its **left**, so the rose is rotated by
  **−heading**; a rose that turns with the heading points the opposite way.
  The needle points the way the car faces, so it sits **outside** the rose —
  a needle inside the rose turns with it and always says north.
- **The GPS course must not overwrite the compass.** `CLLocation.course` is
  the direction of *travel*, not the direction the car faces, and while the
  car is slow it is mostly the GPS's noise. The compass is the heading; the
  course is the fallback for a device without one. The last writer wins, so
  the noisy writer must not be the one that writes last.

## Gotchas from the twelfth pass (2026-11-04, the compass again)

- **A broken log capture reads as a missing callback.** `idevicesyslog` prints
  *"Waiting for device with UDID … to become available…"* and exits when the
  phone drops off the USB bus — and a capture that caught only **three** lines
  was read as *"the heading callback never fires"*. It does fire: the same
  capture held `locationManager:didUpdateHeading:` twice. **Check the line
  count of a capture before believing its contents**, and use
  `xcrun devicectl device process launch --console` when the phone is the
  only source — it bridges the app's stdout and needs no log daemon.
- **CoreLocation reports the heading's **error**, not its noise.**
  `headingAccuracy` was **27.58** on a phone lying flat on a desk: there is
  no usable horizontal field to read a heading from, so the error grows into
  the tens of degrees. Two readings a second apart differed by **1.06°** —
  the *noise* is small, the *error* is huge. A heading that is out by more
  than twenty degrees is not a direction, and a needle that follows it points
  the wrong way. The gate is on the accuracy, and the GPS's course takes
  over; the screen says **GPS COURSE** so the user knows which one they are
  looking at.
- **A filter that counts readings is not a filter.** The magnetometer
  delivers several times a second and the GPS once a second, so "close a
  third of the gap per reading" smooths one source and not the other — and
  CoreLocation delivers its readings in **bursts**: two readings measured a
  second apart were handed over **128 ms** apart. The filter therefore runs
  on a **clock** (`1 - exp(-dt / tau)`), so the needle moves by how much
  *time* has passed and a burst moves it as little as one lonely reading.
  The clock is the **arrival**, not the reading's own stamp: what the user
  sees is when the needle moved, not when the field was measured — and a
  buffered reading's stamp can be *older* than the last one applied, which
  would stall the filter. The seam takes the arrival time for exactly this
  reason — a test that cannot drive the clock cannot pin this down.
- **A magnetic needle and a rotating card are two different instruments.**
  The card turns and a **lubber line** stays put (a heading indicator), or
  the needle points north and the *bezel* turns (a magnetic compass). The
  app had the card turning **and** a red needle fixed at the top, so the
  needle said "north" while the letters said something else — which is what
  "the compass shows the wrong direction" meant. One marker, one colour
  scheme: red is the card's **N**, green is the car's direction.

## Gotchas from the fifteenth pass (2026-11-04, the security review)

- **An `NSError`'s description carries the URL that failed — and the URL
  carries the token.** `String(describing: itm.error)` puts Plex's
  `X-Plex-Token`, Jellyfin's `api_key` and Xtream's password into the
  device's log, which is readable by anything attached to the phone (Xcode's
  console, `idevicesyslog`, a sysdiagnose upload). Log the **host and the
  file name** instead (`CredentialRedactor.safeForLog`), and never the raw
  URL a user typed: a pasted `https://user:password@host/` is a password in
  the log.
- **A token in a URL path is the only lock on a LAN-served stream, and 32
  bits is not a lock.** The screen stream is served over the local network
  and every path carries the token, so `String(UUID().uuidString.prefix(8))`
  — 2³² guesses — was the whole of its privacy. The token rides in a URL path
  and in the relay's announcement line, and hex needs no escaping in either.
  **A v4 UUID is 122 bits of entropy, not 128** — the version and the variant
  take six of the bits — so a bearer token that matters is better made from
  the random source directly: 32 bytes of `SecRandomCopyBytes` in hex is 256
  bits, and the comparison against it is **constant time** (a timing
  difference says how much of the token was guessed right).
- **A test that has never run is not a test.** AC150 was written, the AC
  trace said "151 rows ↔ 151 test names, the same set", and the test was
  **wrong** — it asked for a token without dashes while the code produced
  `UUID().uuidString`'s dashed form. It stayed wrong for hours because the
  phone was off the USB bus and the standalone harness **only exercised the
  redaction** (AC151), never the token. The device suite caught it in one
  run. A green harness says nothing about what it did not run, and the
  trace says nothing about whether a test's **body** is right.
- **The app and the broadcast extension share no secret.** They live in
  different processes and share no container (an App Group would need another
  Apple-granted capability), so the relay's announcement on the loopback
  port **47311** cannot be authenticated: any app on the phone can announce
  a stream of its own. Closing that needs an App Group or the user's
  confirmation — **ask first**.

## Gotchas from the sixteenth pass (2026-11-04, the whole browser mechanism)

- **A content rule list must be applied once, not on every navigation.**
  A `WKWebViewConfiguration` is copied when the web view is made, but its
  `userContentController` is a **shared reference** — so
  `removeAllContentRuleLists()` + `add()` on the live controller tears the
  content process's rule store down **under the page that is loading**. The
  device's own log shows what that does: `GPUProcessProxy::gpuProcessExited:
  reason=Crash` and `WebProcessProxy::processDidTerminateOrFailedToLaunch:
  reason=Crash`, with **no crash report** from the app. The rules are applied
  **once** now, and `apply(to:)` says whether it changed anything so the
  caller knows whether the page has to be loaded again.
- **An empty address IS the start page.** The crash handler emptied the
  tab's address, so a page whose web process died was thrown away and the
  user was back at the home screen — the user's *"it crash the browser tab
  and redirect tom home screen"*. Keep the address and **say** what happened.
- **`objectWillChange` fires *before* the value changes.** A mirror that
  reads the old value inside `objectWillChange` is always **one change
  behind** — the address bar showed the page's *previous* address. The
  `$published` publisher carries the **new** value; subscribe to that.
- **Two text fields, one `@State`, is one field.** The address bar and the
  start page's own search box shared a binding, so what was typed in one
  appeared in the other and the change handlers wiped it. Each box has its
  own state, and the bar is only filled **while it is empty** — filling it
  over what the user has typed is what made the typing look like it did
  nothing at all.
- **`presentTemplate` accepts an action sheet, an alert and voice control —
  nothing else.** `presentSearch()` could therefore **never** work: the
  presentation failed every time and the Search button did nothing at all. A
  search template is **pushed** (`pushTemplate`) instead.
- **A `CPSearchTemplate` cannot carry a navigation bar button.** It does not
  conform to `CPBarButtonProviding` (only `CPListTemplate`, `CPGridTemplate`,
  `CPContactTemplate`, `CPInformationTemplate`, `CPMapTemplate`,
  `CPPointOfInterestTemplate` and `CPVoiceControlTemplate` do), so a pushed
  search has **no way back** except a row of its own list.
- **A search template's delegate is `weak`.** The app has to hold it, or the
  results stop coming.

## Gotchas from the seventeenth pass (2026-11-04, the page the car asks for)

- **The tab the app shows has to be shared state.** It was a `@State` inside
  `MainTabView`, so **nothing outside the view could change it**: the car
  asked for a page, the page opened on the phone's browser tab, and the phone
  stayed on the tab it was on. The share the car needs captures **the phone's
  screen** — so the page has to be *on* the screen, or the car shares the
  wrong one and both screens show nothing. The selection is shared
  (`AppTabSelection`) and the car's page request brings the browser forward.
- **A row added to a list breaks every test that indexes it.** The way back
  out of a search is a row of the search's own list, and making it the
  **first** row broke two older tests that took `results.first` to be the
  channel (AC69) and the typed text (AC99). Look the row up **by its text**.
  The repo's own rule — *"a test that indexes rows by position takes the
  whole test runner with it"* — is about crashes; this is the other half of
  it: the test does not crash, it **fails**, and it fails for a reason that
  has nothing to do with the code it is about.
- **The CarPlay Simulator's "No Devices Connected" is the cable.** Over Wi-Fi
  the phone is a perfect test target — the whole suite runs on it — but the
  simulator lists **no device at all**, because Xcode 27 attaches to physical
  devices over USB only. Check the *Sessions* menu before blaming the app:
  the templates are covered by the tests, and the last mile needs the phone
  on the bus.

## Gotchas from the eighteenth pass (2026-11-05, the car's own browser and keyboard)

- **There is no web template in CarPlay — there is no web template at all.**
  `CarPlay.framework` on iOS 27 carries `CPActionSheetTemplate`,
  `CPAlertTemplate`, `CPContactTemplate`, `CPGridTemplate`,
  `CPInformationTemplate`, `CPListTemplate`, `CPMapTemplate`,
  `CPNowPlayingTemplate`, `CPPointOfInterestTemplate`, `CPSearchTemplate` and
  `CPTabBarTemplate` — and **nothing** that can hold a web page. A template
  browser is a text field and a list of links, so it can only ever be a
  **remote control for the phone**. The app's own car screen — the one with a
  real `WKWebView`, the toolbar and the zoom control — lives in the
  **external-display** scene (`ExternalDisplaySceneDelegate`), and the system
  opens that scene **only when the app asks** for it.
- **A phone refuses the second scene.** `UISceneSessionActivationRequest(role:)`
  + `UIApplication.activateSceneSession(for:errorHandler:)` is the only way to
  ask for the app's own car screen, and on a phone it answers *"The current
  device does not support multiple scenes."* The app's own log says it
  (`the car's own screen was refused: …`), so the question is answered by the
  device's unified log, not by guessing. The ask is harmless where it is
  refused — the fallback is the phone.
- **`CPSearchTemplate` has no keyboard — the keyboard is the car's.**
  The header carries `delegate` and nothing else; there is no `keyboard`
  property and no way to bring one up. The keyboard that comes up floats over
  the **bottom of the list**, and a **row under it takes the key presses**
  instead of the keyboard (the user's *"the keyboard clicks the row behind
  it"*). Measured on the simulator's 1920×1080 screen: the keyboard covers
  the bottom ~27 % and a result row's band is **full width**, so a key press
  lands on the row behind it. The fix is the app's: **keep the list short** —
  a row that is not under the keyboard cannot steal a key press. The whole
  catalogue belongs in the Browser tab's own list, one tap away.
- **The simulator's floating keyboard is the car's, not the app's.** It is
  drawn by the simulator's own `atve-kit` (`Assets/atve-kit/TextInput/
  Keyboard.json` holds the key labels) and it is the same one Apple's own
  CarPlay apps get. There is no "native keyboard" an app can ask for instead —
  the app's only lever is what it puts **under** the keyboard.
- **A site has to answer to its name.** The results matched the **address**
  only, so "HBO Max", "Prime Video", "Sony LIV" and "iQIYI" found nothing:
  "HBO Max" is nowhere in "max.com", and the name is what the user reads on
  the row.
- **`CPSessionConfiguration` cannot be asked for.** `limitedUserInterfaces`
  (`.keyboard`, `.lists`) is the car's way of saying *"the keyboard here is a
  limited one"* — but there is **no accessor** for a `CPSessionConfiguration`
  on `CPInterfaceController`, on the scene or in UIKit (iOS 27 SDK), so the
  app cannot read it. The short list is the app's own answer to the same
  problem.

## Gotchas from the nineteenth pass (2026-11-05, the picture of the page)

- **A web view with no window at all still renders.** Measured on the iPhone
  13: `WKWebView(frame: 1280×720)` that is **never in a window** produced five
  of five good pictures (`takeSnapshot`), 11–21 ms each, and its layout
  viewport was **exactly 1280×720** — the car's 16:9. A web view **in a
  window** loses the safe area and lays out at **1280×639**, so the page is
  cut off at the bottom. The car wants the window-less one: the page is drawn
  for the car's screen, not for the phone's.
- **The picture is three times the view.** `takeSnapshot` returns a
  **3840×2160 px** image whose `image.size` is 1280×720 **points** (3× the
  scale). A sampler that mixes the two — `image.size` for the maths and
  `cgImage` for the pixels — looks at the wrong place entirely: the "centre"
  of a 1280-point-wide picture is pixel 640, not 1920. That is how a correct
  page was measured as a black square in the wrong spot.
- **The encoder's canvas and the web view's layout disagree about which way
  is up.** The page's layout is top-down; the picture is written through
  Core Image, which is bottom-up. A marker at the **top** of the page can
  therefore be at the **bottom** of the picture. A test that looks for a
  marker has to look for it at both ends — or the marker has to be at the
  **centre**, where the two agree.
- **A page the car asks for has to take the player from the phone's share.**
  `ScreenShareService.tearDown()` calls `PlaybackManager.stopScreenShare()`, so
  the phone's own screen share has to be stopped **before** the car's browser
  takes the player — or the share's end would kill the browser's picture.

## Gotchas from the twentieth pass (2026-11-05, the offline vault on the car)
- **`-11870` is `AVErrorExternalPlaybackNotSupportedForAsset`, and it is about
  the **asset**, not the media stack.** The iOS 27 SDK header says so
  (`AVError.h`: `AVErrorExternalPlaybackNotSupportedForAsset = -11870`). It
  fires **the instant** the car's external route goes active
  (`isExternalPlaybackActive` → true) and it kills the item **permanently**
  (`status == .failed`) — so the video dies on the phone *and* on the car. The
  only difference between the vault and the browser was the **URL**: the vault
  handed the player a `file://` URL inside the app's container, the browser
  hands it an `http://127.0.0.1:…` URL. The car's display is fed by the
  system's **own** video target — a process that runs **outside** the app's
  sandbox — and it cannot open a sandboxed file. A loopback URL is reachable
  by every process on the phone. **A vault file that goes to the car has to be
  served over HTTP.**
- **A number in an old log is not an error.** The two `11870` hits in
  `build/syslog_diags.log` are `siriknowledged`/Biome noise where "11870"
  appears inside a UUID — not AVFoundation at all. Read the lines **around**
  the hit before believing it.
- **Re-attaching an item that is already playing restarts it.** The player
  resets the item to zero while it prepares it again, and a seek issued right
  after the attach is thrown away with it (the status stays `readyToPlay`, so
  there is no status event to hook). Measured: the playhead jumped to 0.0
  after **every** offer of the re-offer ladder. The offer brings a **new** item
  for the same asset, and the new one starts where the old one was — and the
  **observers belong to the item**, so the new one has to be watched too (or
  the phone says "Loading Stream…" for ever).
- **`devicectl copy from` flattens a directory** and `copy to --destination
  <path>` writes a **file**, while `--remove-existing-content true` on a
  directory destination replaces a file with the directory. Copy the vault
  **file by file** when it has to survive a test install.
- **A device test install can wipe the app's container** — the user's own
  offline vault lives there. Copy it out before a run and put it back.
- **`idevicesyslog` dies when the app is reinstalled**, and the app's own
  `os_log` output does **not** appear in it. Use
  `xcrun devicectl device process launch --console` for the app's own lines.
- **The CarPlay scene connects only when DrivePlay is open on the car's
  screen** — the car opens it, not the app. A scene that never connects is the
  simulator, not the code.
- **A phone that is off the USB bus and out of Wi-Fi range is gone:**
  `devicectl device info lockState` answers *"not able to fulfill the
  requested usage assertion requirements"* (`CoreDeviceError 4016`) with an
  **empty** `CurrentlyAssertableStates`, and the phone is not in
  `xcodebuild -showdestinations`. That is not a code failure — wait for it.
- **A server that only needs Foundation + Network can be checked without the
  phone.** Compile the **real** source file for the Mac (`swiftc -o check
  VaultFileServer.swift main.swift`) and answer it with `URLSession` — the
  XCTest needs a device, this does not. `scripts/vault_server_check.sh` does
  exactly that for the vault's file server.
- **`NWListener(using: .tcp, on: .any)` asks the phone for the local-network
  permission** and leaves the listener in `.waiting` until the user answers.
  Bind the **loopback** instead:
  `parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)`.
  The car's video target runs on the phone, so it never needs the LAN — and
  the user's own media has no business on the network.
- **The serving belongs in `play(channel:)`, not in a method of its own.** The
  vault's file is served over HTTP so the player's URL is one every process on
  the phone can fetch — but a **separate** method that only the vault's tap
  calls leaves the watch history's *"watch again"* row handing `play(channel:)`
  a `file://` URL, and the video dies on the car the second time it is played.
  The history's row is a **caller** like every other: fix it once, where all
  callers route through it.
- **The vault's token is 256 bits, and it is compared in constant time.** 32
  bytes from `SecRandomCopyBytes` in hex — a v4 UUID carries 122 bits, not the
  128 its length suggests. The server binds to the **loopback**, so the token
  is the only thing between another app on the phone and the user's own media.

## Gotchas from the twenty-first pass (2026-11-16, the black screen and the car's browser)

- **An `@objc(Name)` attribute strips the module prefix — and the manifest
  names the class by its qualified name.** `@objc(CarPlaySceneDelegate)` gives
  the class the runtime name "CarPlaySceneDelegate", while the manifest asks
  for "CarTV.CarPlaySceneDelegate" → `NSClassFromString` answers **nil** → a
  scene built from the manifest gets **no delegate** → CarPlay raises an
  NSException in `-[CPTemplateApplicationScene _deliverInterfaceControllerToDelegate]`
  → SIGABRT → the app dies → the phone's screen is black. The path where UIKit
  asks the app (`configurationForConnecting`) sets `delegateClass` to the class
  **object**, so it masks the mismatch: the crash only happens when the **car
  launches the app**, because that is the one path where the manifest is the
  only source of the configuration. AC177 reads the **running** app's manifest
  and pins it.
- **The `__objc_classname` section of the built binary is the runtime-name
  table.** A class with `@objc(Name)` appears there under the bare name; a
  class without one appears mangled (`_TtC5CarTV20CarPlaySceneDelegate`) and
  its runtime name is the module-qualified one. `otool -s __TEXT
  __objc_classname` on the built dylib answers "does this name resolve?"
  without a device.
- **The CarPlay Simulator's car display *does* have accessibility elements.**
  The app icons are `AXButton`s whose `AXIdentifier` is the icon's SF Symbol
  ("car.fill", "house", "siri", "play.fill" …), so a tap can be made **by
  name** (`AXPress`) instead of by a blind coordinate click — and the screen
  can be read without a screenshot.
- **CarPlay's private vehicle-window role is real.** The SDK does not declare
  it (there is no `UISceneSessionRoleCarPlay` in any header), but UIKitCore
  exports the private symbol `__UIWindowSceneSessionRoleCarPlay`
  (`UIKit.tbd`), and the shipping app **CarDash** declares the role
  `"UIWindowSceneSessionRoleCarPlay"` → `UIWindowScene` in its manifest
  (`~/cardash-re/out/Info.plist.txt`). The SDK's own API has **no** web
  template: `CPInterfaceController` accepts only `CPTemplate`s.
- **A CarPlay session dies with the USB connection and with a reinstall.**
  The simulator's car display then freezes on the last frame (its AX tree
  still lists the old buttons) and the app's CarPlay scene never connects —
  the app is fine, the *link* is gone.

## Measurement traps (both of these caused wrong conclusions here)

- **`set -o pipefail` turns `… | grep -q` into a false negative.** `grep -q` exits at
  the first match, the writer on the other side gets SIGPIPE, and `pipefail` reports the
  whole pipeline as failed — so a profile that *does* carry the key reads as missing.
  Do the matching without a pipe (capture the output, then compare). The same trap
  catches `security cms -D -i … | grep -q`.
- **A path with a space breaks `for x in $(command)`.** The provisioning profile folder
  is `…/UserData/Provisioning Profiles` — word-splitting turns one path into two words
  and the profile is never read. Read the paths line by line, quoted.
- **A test that reads the repository cannot run on a device.** `#filePath` is baked
  into the test bundle at build time, so on the phone the path points at the Mac the
  bundle was built on and the file is not there. Seven contract tests read a repo file
  (`project.yml`, the entitlements, the scripts) and failed on the device for that
  reason alone. They now skip when the checkout is not on the machine
  (`RepositoryFixture.skipUnlessPresent()`).
- **iOS does not refuse a privileged port.** Port 1 binds fine on the phone, so a test
  that proves "the listener cannot listen" with a privileged port waits for a failure
  that never comes. Take a port that is **already bound** — that is refused everywhere.
- **A listener on every interface asks a phone for the local-network permission.**
  `NWListener(using: .tcp, on: port)` binds on all interfaces, so on a phone the
  system shows the *"find and connect to devices on your local network"* prompt and
  the listener waits in `.waiting` — the test's expectation never comes. Bind the
  **loopback** interface, like the app's own relay does:
  `parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)`.
- **ReplayKit waits for the user's consent, so a capture on a phone never ends.**
  `RPScreenRecorder.startCapture` shows the system prompt and stays pending until
  the user answers — the completion handler is not called, no frame arrives, and the
  share sits in "Starting…" for ever. The Simulator instead ends the capture at once
  without a frame. A test that needs "a capture that ends without a frame" cannot
  produce it with the real capture on a device: drive it through the capture seam
  (`ScreenShareService(capture:)`).
- **A device test that reads the session has to set the session up itself.** The app
  under test shares one process with the tests: the session the app left behind is the
  session the test meets. Probe the session (print the category, the mode, the options,
  the input format) before believing a failure — the first guess about the voice
  search was wrong twice.

- **Do not re-sign a built simulator app to inspect its entitlements.** `codesign --force
  --sign - --entitlements …` replaces the signature and breaks the embedded
  `ScreenRelay.appex` signature, so the app then fails to launch with
  `FBSOpenApplicationServiceErrorDomain code=3`. Simulator entitlements live in the Mach-O
  `__TEXT,__entitlements` section (not the code signature), so `codesign -d --entitlements`
  legitimately prints `{}`. Read them with `otool -s __TEXT __entitlements`, and remember
  `otool` prints each 4-byte word **byte-swapped** — decode by reversing every 4-byte group.
- **A missing file is not proof that a feature is absent.** Two wrong conclusions came from
  inferring "not installed" from a path that no longer exists in Xcode 27. Check what the tool
  actually uses before concluding a runtime is missing.
- **The app's appearance is the app's own business.** `UIUserInterfaceStyle: Dark` sits in
  `project.yml` (the source of truth for `Info.plist`), so the phone's light/dark setting does
  not turn DrivePlay light — the app is dark on every tab, every sheet and every window. The
  **car** is not affected and cannot be: the car paints its own chrome, and the app only hands
  it titles, icons and artwork. Read the key from the *running* app in a test
  (`Bundle.main`), never from a copy in the repository.
- **A test that fails on the phone may be the phone.** A phone that **locks itself** takes the
  app under test down with it: the app is backgrounded, the in-flight work stops, and XCTest
  reports *"Restarting after unexpected exit, crash, or test timeout"* and blames whichever test
  was running — on code that never changed. **No crash report is written** (a kill, not a crash),
  and the only proof is in Xcode's own output: *"Xcode cannot launch CarTVTests on Rushabh's
  Iphone because the device is locked."* Only the app can hold the idle timer, so the app holds it
  while the tests run (`isIdleTimerDisabled`, set when `XCTestConfigurationFilePath` is in the
  environment). Do not blame the code, the thermal state or the memory before reading that
  message — and check `xcrun devicectl device info lockState` and
  `xcrun devicectl device info displays` (the backlight state) before believing a device failure.
  `idevicesyslog` is installed and gives the device's own log while the run happens.
- **A killed app has a signature — look for it before reading a "failed" test as a bug.**
  Six tests failed in one device run with **no assertion message at all**, and each was followed by
  *"Restarting after unexpected exit, crash, or test timeout"*. The three tells: **no crash report**
  in the phone's crash-log folder (a crash always writes one), the xcresult says *"the test runner
  exited with code 0"* or *"Test crashed with signal kill"*, and **the previous instance was still
  holding the app's listener port** when the next one started (*"Address already in use"*) — which
  means the old process was **suspended in the background**, not dead. Re-run the same tests with
  the phone **unlocked**: all six passed in 21.7 s, and the code was never at fault.

## Data model gotcha

`PlaylistStore` keeps a `@State`-free cache (`cachedChannelsBySource`, `cachedGroupsBySource`,
`cachedGlobalGroups`) rebuilt by `rebuildIndex()`, which `saveChannels()` calls.
`toggleFavorite` therefore refreshes the cache correctly — but views that keep their **own**
`@State` snapshot of `[Channel]` (the docked player's grid, `GroupDetailView`) go stale and
must be kept in step on toggle.

`PlaylistStore.groups` applies the handset search box; `PlaylistStore.allGroups` is the
unfiltered index. A second screen (CarPlay) must read `allGroups`, or typing on the phone
shrinks the car catalogue. `allGroups` is only as fresh as `rebuildIndex()` — call it
directly if you replace `channels` without going through `saveChannels()`.
