# AGENTS.md — DrivePlay / CarTV app

Project-specific rules for this repo. The global `~/.claude/CLAUDE.md` still applies; this file wins on conflict.

## Build & test

```bash
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES test
```

**On the phone** (the CarPlay video surface and the broadcast can only be
exercised there, and Xcode 27's CarPlay Simulator hosts physical devices only):

```bash
scripts/device_test.sh          # waits for the phone, then runs the suite on it
```

**The Simulator build has to be signed** (ad-hoc is enough). An unsigned app has no
`application-identifier`, so the Keychain refuses every write with `-34018`
(`errSecMissingEntitlement`) — the credentials of a source cannot be stored at all.
`CODE_SIGNING_ALLOWED=NO` still builds and installs, but the Keychain is dead in that build.

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
