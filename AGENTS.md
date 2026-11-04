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
