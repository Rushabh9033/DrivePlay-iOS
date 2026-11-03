# Changelog

All notable changes to DrivePlay (target `CarTV`) are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- **The voice search showed "com.apple.coreaudio.avfaudio error 1852797029"
  and never listened.** The player holds the audio session as `.playback` — a
  category with **no input route** — and the recorder's engine was born on
  that session, so its input node carried a 0 Hz format and refused to start
  (*"IsFormatSampleRateAndChannelCountValid"*). The session is now handed over
  to the microphone before the engine is built, the engine is built for the
  recording, and the player's session comes back when the microphone is
  released — a video that is playing gets its sound back with it.

- **The player's audio session was never configured.** The session was set up
  as `.playback` with the AirPlay and Bluetooth options — and those options
  are only valid with `.playAndRecord`, so the system rejected the whole call
  (`OSStatus -50`) and the session was **never activated**. The AirPlay route
  to the car's display was therefore never offered. The category is now the
  one the options belong to: `.playback`, no options.

- **The contract tests failed on the phone.** Seven of them read a file from
  the repository (`project.yml`, the entitlements, the scripts), and the paths
  baked into the test bundle point at the Mac it was built on — the phone has
  the app, not the checkout. A file that is not on the machine says nothing
  about the contract, so those tests now skip on a device instead of failing
  there.

- **The "a relay that cannot listen" test could not fail on iOS.** It proved
  the failure with a privileged port, but iOS does not refuse a port below
  1024 — the bind simply succeeded and the test waited for a failure that
  never came. It now takes a port that is **already bound** — and it binds it
  on the **loopback** interface, like the app's own relay: a listener on every
  interface asks a phone for the local-network permission first and then waits
  for the answer. The listener that occupies the port also needs a connection
  handler: one started without one never creates its socket, never reaches
  `.ready`, and leaves the test waiting for a bind that was never going to
  happen while the port itself was free.

- **The "a capture without frames falls back to the demo" test could not
  happen on a phone.** ReplayKit waits for the user's consent there and never
  ends on its own, so the share sat in "Starting…" for ever and the demo never
  took over. The capture is now a seam (`ScreenShareService(capture:)`), so the
  test can drive a capture that ends without a frame — the same way the
  "this device cannot record" test already drives `captureAvailable: false`.

- **The car's artwork was drawn for the wrong screen.** Apple says it plainly:
  *"images you display in any template should be sized to a display scale matching
  the scale of the `carTraitCollection`, not the scale of the iOS device's main
  screen."* The car is a different display — another aspect ratio, another
  scale — so a logo drawn at the phone's scale arrives on the car either soft
  or resized. The scale of the car's own trait collection is now read when the
  scene connects, and every card is drawn at it.

- **A rebuilt car's screen drew every card again.** The logo cache held the
  *logo*, so a rebuild fetched nothing new — but it also drew every tile from
  scratch. With a playlist of thousands of channels that is the difference
  between a rebuild and a stall, and the rebuild happens on every favourite
  change. The drawn tiles are cached too, so a screen that is rebuilt draws
  nothing that is already on it.

- **The car's display stayed black — the player had nowhere to draw.** A
  video-only `AVPlayerItem` never renders without a video output: CoreMedia
  logs *"video-only item is waiting for video output"*, `timeControlStatus`
  stays `.waiting` and the playhead never leaves zero, while the stream itself
  is fine. On the car the phone shows no player at all, so nothing owned an
  `AVPlayerLayer` and the item never started. The app now keeps a small output
  of its own whenever the phone shows no picture, and gives it up again the
  moment the phone's own player comes back — one output at a time.

- **The broadcast never reached the car — the relay was not listening yet.** The
  relay only started when a CarPlay row was tapped or the phone's screen
  mirroring tab appeared, but the user starts a broadcast from the Control
  Center: the extension announced its stream into a relay that was not there
  yet, and the share never began. The relay now listens from launch.

- **The test bundle could not be signed for a real device.** `CarTVTests` had
  no development team, so `xcodebuild test` against the phone failed with
  *"Signing for CarTVTests requires a development team"*. The target is signed
  like any other app now, so the suite runs on the device.

- **The picture never reached the car.** A CarPlay video app has to support
  AirPlay video streaming — the car's display is an AirPlay destination ("Rev
  up your CarPlay app", WWDC26) — but the player allowed external playback only
  on the screen-share path. Every channel played from the car therefore played
  on the phone and left the car's display black, with nothing logged. The
  player now allows external playback on every path.

- **Tapping any row on the car killed the app.** Every channel and playlist row
  presented the now-playing template modally, and CarPlay **throws an
  `NSException` when a template call fails and no completion handler was given**
  — an uncaught ObjC exception, so the process aborted (SIGABRT) and the app
  died on the first tap. The now-playing screen is the system's to present: the
  rows carry a `playbackConfiguration`, and CarPlay shows the media presentation
  itself when an item is selected, so the app now only configures the shared
  template. Every other template call (the channel list, the search) carries a
  completion handler as well, so a failed call is logged instead of being fatal.

- **Starting the relay tore down the share that was already running.** The
  relay only listens — it shares nothing until the broadcast extension
  announces its stream — but it stopped whatever was being shared *before* the
  broadcast arrived. The relay now only listens, and the broadcast replaces the
  running share when it turns up, which is what makes it safe to leave the
  relay running while the user picks the broadcast.

- **The app could die when the screen capture delivered no frame.** The encoder
  only starts with the first frame, so a capture that delivers nothing leaves a
  writer that was never started — and closing such a writer throws an
  `NSInternalInconsistencyException`, which takes the app down with it. The
  Simulator does exactly that, and so does a phone that refuses to record the
  screen while CarPlay is connected (`RPRecordingErrorCarPlay`): tapping the
  car's "Screen Mirroring" row could kill the app. The writer is now only
  closed when it actually started.

- **Waiting for the car's broadcast blocked the phone's own share.** The relay
  latched the "starting" state while it waited for the broadcast extension, so
  the capture and demo buttons stayed disabled — and the phone never said that
  it was waiting. The relay now only listens: the share state is untouched
  until a stream really arrives, and the waiting is visible.
- **Ending a share took the relay down with it.** The listener was stopped
  when the share was torn down, so the next broadcast was not picked up until
  the car's row was tapped again. The listener now lives as long as the car is
  connected and stops when the car disconnects.

- **The fragment window was read under a lock and written without one.** The
  encoder fills the fragments on its own queue while the HTTP server serves
  them on another; the readers took the lock and the writers did not, so the
  lock protected nothing. A Swift array mutated while it is read is undefined
  behaviour — not a glitch — so the fragments are now filled and read under
  the same lock.

- **A broadcast address that arrived in two pieces was thrown away.** The
  listener did one read and parsed it as a whole line, but the network can
  split a line: the first read then held half an address, which was not an
  address, so it was dropped — and the extension does not send it again. The
  phone's screen never reached the car, with nothing to show for it. The
  listener now waits for the whole line.

- **A relay that could not listen said nothing.** The bind fails *after*
  `start()` has returned, so the app waited for an announcement that could
  never arrive and the car showed nothing with no reason given. The failure is
  now reported, and the app says so instead of waiting.

- **The screen share could never work from the car.** iOS refuses to record the
  screen while CarPlay is connected (`RPRecordingErrorCarPlay`, "Failed to
  start recording due to carplay being active"), so the capture behind the
  CarPlay row always failed and the share fell back to the demo picture — the
  driver saw a fake animation instead of their phone. The car's row now waits
  for a broadcast (the WhatsApp-style mechanism) and the failure says what to
  do instead of failing silently.
- **CarPlay was asked for a video surface the app was not entitled to.** Every
  row asked for `.video` presentation, and the system refused the playback
  ("presentation is video but app does not have the video entitlement") — the
  car got no picture and the log filled with errors. The app now asks for video
  only when this build carries the CarPlay video entitlement, and falls back to
  the now-playing screen when it does not.
- **`scripts/carplay_grant.sh check` always said MISSING.** The provisioning
  profile folder has a space in its name ("Provisioning Profiles"), so the
  paths were word-split and the profiles were never read; `pipefail` with
  `grep -q` also turned a good profile into a failed one. The check now
  reports the profile that carries the entitlement.

- **The car shelves were rebuilt three times at launch.** The store
  republishes its channel list on every save, and the publisher also fires
  once on subscription, so the shelves were torn down and rebuilt — every
  card, every category — for data that had not changed. A rebuild now
  happens only when the channel list or the favourites actually differ.
- **The install helper only worked on the machine that wrote it.**
  `scripts/auto_install.sh` hardcoded one iPhone's UDID and one absolute
  DerivedData path, and looped forever when that phone was not connected —
  the job hung with no way out. The device is now detected at run time (or
  passed as an argument), the built `.app` is located in DerivedData, and the
  wait for a phone is bounded and ends in a clear error.
- **The offline vault could lose imports.** Two files with the same name (e.g.
  `clip.mp4` from two different folders) were both stored as `clip.mp4`, so the
  second import overwrote the first and the vault ended up with two entries
  pointing at one copy. Stored files are now prefixed with a fresh id.
- **The offline vault index was written non-atomically.** A write interrupted by a
  crash left a truncated `index.json`, and the vault then failed to load — every
  import looked gone. The index is now written atomically.
- **Voice search never worked.** The overlay was never presented, `startRecording`
  had no callers, and neither the speech-recognition nor the microphone permission
  was ever requested — the sheet showed "Listening…" while nothing was recording.
  The microphone button on Home now opens it, the permissions are requested, and a
  spoken channel or category name starts playback. A tap left installed on the audio
  input node (when the engine failed to start) also trapped the next recording; the
  tap is now always detached.
- **Plex sign-in could never complete.** `PlexPin` required a JSON key `expiresAt`,
  which Plex does not send — it returns `expiresIn` and `createdAt`. Every pin
  response therefore failed to decode with `keyNotFound`, so neither creating a
  pin nor checking it could succeed.
- **Unbounded channel-logo cache.** The `NSCache` holding channel logos had no cost
  limit, so it grew with every logo ever seen and evicted nothing. It is now capped
  at 32 MB and each image is stored with its approximate byte cost.
- **M3U parsing — channel titles with commas.** The title separator was found by
  scanning for the *last* comma on the `#EXTINF` line, so a title containing a
  comma (`ESPN, Sports`) was truncated. The separator is now found by skipping
  over quoted attribute values.
- **M3U parsing — group titles leaking between entries.** An entry without a
  `group-title` inherited the *previous* entry's group. Group membership is now
  derived only from the entry's own tags, and `#EXTGRP` applies only to the
  entry it belongs to.
- **Xtream Codes — credentials breaking the request URL.** Usernames and
  passwords were interpolated raw into the query string and the stream path. A
  password containing `&`, `#`, `?` or `/` truncated the request (HTTP 401 or a
  404 on every channel). Credentials are now percent-encoded.
- **Xtream Codes — unplayable channels.** A channel whose stream URL cannot be
  constructed was silently given the API endpoint as its stream URL, handing the
  player a JSON document. Such channels are now dropped.
- **Xtream Codes — multi-category streams.** A stream reported with several
  category ids (`"1,2"`) was grouped under no category at all. It now uses the
  first matching category.
- **Screen mirroring on the iOS Simulator.** The Cast tab latched a "mirroring
  active" state *before* checking `RPScreenRecorder.isAvailable`, which is
  always false in the Simulator. Every later attempt returned early and the tab
  spun on a waiting card forever. It now reports that screen recording is not
  supported in the Simulator.
- **CarPlay home chevrons.** The scroll up/down chevrons were positioned
  against the view's bounds instead of the scroll container's, putting the
  up-chevron 48pt too low and the down-chevron 26pt below the bottom of the
  screen, where it could not be tapped.
- **Video player skip buttons.** The ±10s buttons were created visible, so the
  first tap on the video hid them instead of revealing them. They now start
  hidden.
- **Favorites.** The docked player's channel grid and the group detail swipe
  action render a snapshot of the channel list; favoriting a channel updated
  the store but not the snapshot, so the heart never changed. The snapshot is
  now kept in step.
- **Stream health.** A source with 500 ms or more latency was reported as
  "fair", which made the "poor" state unreachable even though the UI branches
  on it. It is now reported as "poor".
- **Screen mirroring outlived the external display.** The capture was only
  stopped by the Cast tab's close button; a tab switch or the external display
  going away left the recording running (the recording indicator stayed on and
  the battery drained). The stop path is now shared by all three, and the
  sample-buffer renderer is only touched on the main thread, which is where
  `AVSampleBufferDisplayLayer` requires it.
- **App Transport Security allowed plain HTTP to every host.** The app
  declared `NSAllowsArbitraryLoads`, so any server address could be fetched
  over an unencrypted connection. Plain HTTP is now limited to the local
  network (`NSAllowsLocalNetworking`), the in-app browser keeps its own
  exception, and every server URL the app builds goes through one policy that
  picks `http` for local hosts and `https` for everything else.
- **Server credentials were stored in the clear.** The username, password and
  access token of a source were JSON-encoded into `UserDefaults`, and the
  Xtream stream URLs (which carry the credentials in their path) and the
  Jellyfin URLs (which carry the token in the query) were written to
  `Documents/saved_channels.json` and to the watch history. The secrets now
  live in the Keychain, the files on disk hold placeholders, and the URLs get
  their credentials back when they are played.
- **A blocked server was a mystery.** When iOS refused an unencrypted address
  the app showed the raw system error, which does not say what to do about it.
  It now says that the address uses an unencrypted connection and what to use
  instead.

### Added

- **A switch between the car's display and the phone.** The car's display is an
  AirPlay destination — a CarPlay video app has to support AirPlay video
  streaming ("Rev up your CarPlay app", WWDC26) — so the picture travels the
  AirPlay route: the player offers the video to the car's display
  (`allowsExternalPlayback`), the system reports the route back
  (`isExternalPlaybackActive`), and a "Play on Car Display" pill opens the
  system's own device list. When the car is connected, a "Car connected" banner
  appears with "Play on Phone" to take the picture back and a pause button.
  Nothing about it is a mock: every row acts on the real route.

- **The picture keeps playing when the app is minimised or the screen is
  locked.** The player now keeps the video alive in the background
  (`audiovisualBackgroundPlaybackPolicy = .continuesIfPossible`, with the
  `audio` background mode), and the scene's phase change puts it back to work
  when the phone goes to the background — so the car keeps the picture the
  phone was showing.

- **The car's screen is a tab bar with four tabs — Home, Favorites, Cast and
  Browser.**
  - **Home** lists the whole playlist under "All" and then every category, each
    with its real count, its own artwork, its channels as horizontally
    scrollable cards (iOS 26+) and a way into all of its entries.
  - **Favorites** is the phone's own list: the same favourites, the same
    instant, kept in step by the store.
  - **Cast** shows where the picture is and what the share does — the real
    state of the player and of the broadcast, with the actions each one allows.
  - **Browser** offers the sites of the app's own browser and opens them **on
    the phone**. CarPlay has no web view — Apple does not allow one — so the
    closest compliant interaction is to drive the phone's browser and let the
    screen share carry the picture to the car.

  The rows carry the `playbackConfiguration` that asks CarPlay for the video
  surface, the logos are fetched once and cached, and every logo is drawn at
  its own aspect ratio on a rounded charcoal card with the green accent — never
  stretched, never clipped.

- **The `screen-capture` background mode.** The share to the car runs with the
  app in the background (the car is driving the app) and the capture runs in
  the broadcast extension, so the app needs to stay alive while the capture
  runs — that is what the mode is for.

- **A broadcast button in the app — the WhatsApp screen share, without the
  Control Center.** The app cannot start a broadcast by itself (iOS always asks
  the user), but it can put the system picker in front of the user: one tap on
  the "Screen Mirroring" screen and one on "DrivePlay Screen Relay" starts the
  share, and the car's display shows the phone's screen. Only the app's own
  extension is offered, so the list holds a single entry.

- **`scripts/carplay_video_install.sh` — the CarPlay video build, in one
  command.** Apple mints the provisioning profile that carries
  `com.apple.developer.carplay-video`; the script takes the profile the
  account holder downloaded, checks that it really carries the entitlement,
  installs it where Xcode looks (moving the profile it replaces aside, so Xcode
  cannot sign with the wrong one), builds the video build for the connected
  phone and installs it. Signing stays on automatic, so no Apple account has to
  be signed in on the build machine.

- **The phone's screen on the car, broadcast WhatsApp-style.** The
  `ScreenRelay` broadcast extension encodes the screen into a live HLS stream
  and serves it; the app picks the stream up and plays it, and the car draws
  it in the now-playing area. This is the capture that works while CarPlay is
  connected: iOS does not allow the app to record its own screen then, but a
  broadcast started from the Control Center keeps running. The two processes
  find each other over the loopback interface — they share no container, so
  the stream address travels in one line.

- **The phone's screen on the car's display — screen sharing, WhatsApp-style.**
  A car screen never shows a mirror, only the video the app plays, so the app
  records its screen, serves it as a live HLS stream and plays that very
  stream; the car draws it in the now-playing area. The share card lives on
  the Cast-to-car screen, and the CarPlay template starts the same share.
  The playlist is served on the local network as well, so a head unit that is
  not CarPlay can open it and watch the screen live.
- **A demo stream for the CarPlay Simulator.** The Simulator has no screen to
  record, so `DemoFrameSource` draws a moving picture and feeds it through the
  same encoder and the same server — the whole chain can be checked there. A
  share whose capture delivers no frame now hands over to it by itself, so the
  CarPlay row works on the Simulator too, and the phone says plainly that a
  demo picture is being shared.
- **The car's "Screen Mirroring" row now starts that demo on the Simulator.**
  The row waited for a broadcast, and no broadcast can arrive there: the phone
  has no screen to record and the extension cannot be started. On the Simulator
  the row now starts the demo picture — the same chain, and a picture on the
  car's screen. On a real phone it still waits for the broadcast: a fake
  picture on a real car would be worse than nothing.
- **`scripts/carplay_simulator.sh`** builds and installs the app in the
  Simulator **with the CarPlay video entitlement**, which is what makes the
  CarPlay Simulator ask for the video surface at all, and prints the two facts
  that decide it. The device build stays on the audio category until the
  portal carries the CarPlay Video capability — a device build that asks for
  video does not sign.
- A `CarTVTests` unit-test target (`CarTV/Tests`) wired into the `CarTV`
  scheme, with 66 tests covering the M3U, Xtream and DLNA parsers, the Plex
  pin response, the offline vault, the CarPlay templates, the car shelves,
  the URL policy, the credential storage, the purchase layer, the CarPlay
  entitlement, the install script and the screen share.
- **A Pro row in Settings.** The paywall existed but nothing led to it. It
  is now reachable, and it says whether Pro is unlocked, offers the upgrade
  with its price, or says that the upgrade is not in the store yet.
- **A local StoreKit configuration** (`Configuration/DrivePlay.storekit`) with
  the Pro product, attached to the `CarTV` scheme — the purchase path can be
  exercised in the Simulator without a Sandbox account.
- **`scripts/run_tests.sh`** — the whole suite in one command, with the
  ad-hoc signing the Keychain needs and an automatic choice of Simulator.
- **`scripts/carplay_grant.sh`** — says whether the local provisioning profile
  carries the CarPlay entitlement, and asks Xcode for a new one that does
  (once Apple has granted the capability).
- **`docs/carplay-video-request.md`** — the step-by-step package for the Apple
  account admin: what to send Apple, the text for every field, and what
  happens after the request is approved. `docs/carplay-video-request-simple.pdf`
  is the same guide in plain language, ready to hand over.
- **A GitHub Actions workflow** (`.github/workflows/tests.yml`) that generates
  the project and runs the same script on every push.

### Changed

- **The video build asks for both CarPlay entitlements.** Apple's profile for
  the app id carries `carplay-audio` and `carplay-video`, and Apple's own
  guidance is to include both when the content suits both: the app then
  appears on **every** car — an app with only the video entitlement does not
  appear at all on a car without "video in car" — and the picture appears on
  the cars that support it. The audio build stays audio-only, so it still
  signs with the old profile.

- **One CarPlay category per build, chosen by a setting.** Apple grants one
  category per app and the capability lives on the app id, so a build is
  either signed with the entitlement or it does not build at all. The build
  setting `CARPLAY_CATEGORY` ("audio" or "video") picks the entitlements file
  *and* tells the app what it was signed with, so the app can never ask
  CarPlay for a picture it is not allowed to have. It is "audio" until the app
  id carries the CarPlay Video capability, and the device build works again in
  the meantime.

- **The CarPlay screen share is a list row now, not a bar button.** Only
  `CPListItem` carries a `playbackConfiguration`, and that is how CarPlay is
  told that the content behind a selection is video — without it the car's
  now-playing area had no picture to draw. The row carries the same video
  signal the channel rows carry.

- **`CarPlayVideoViewController.swift` is no longer a 2,022-line file.** It is
  split into nine files by responsibility — the controller itself plus the top
  bar, the content area, the browser, the video, the mirror, the search, the
  shelves and the actions. The code was moved, not rewritten; the members that
  the extensions share are no longer `private` (Swift's `private` is limited
  to one file).
- **The CarPlay entitlements now include video.** `CarTV.entitlements` asked
  for `com.apple.developer.carplay-audio` only, so the car screen could never
  show a picture. It now asks for `com.apple.developer.carplay-video` (the
  video key is `carplay-video`, not `carplay`) and no longer for the audio key:
  Apple grants **one** CarPlay category per app, so asking for both meant
  asking for two categories and getting neither. Apple grants that capability
  per app: **the device build stops signing until the provisioning profile
  carries it.** The Simulator build is unaffected.
- **The `CarTV` scheme is shared now.** It was defined under a target in
  `project.yml`, which XcodeGen does not write to disk — so no `.xcscheme`
  existed and Xcode silently fell back to an auto-created one, without the
  test target. The scheme is now defined at the project level and lives in
  `CarTV.xcodeproj/xcshareddata/xcschemes/CarTV.xcscheme`.
- **CarPlay now uses the template API only.** CarPlay renders templates — no
  public header in `CarPlay.framework` exposes `UIViewController`, so the
  custom view controller the CarPlay scene used to install on the CarPlay
  window could never render. The scene delegate now builds the car UI from
  `CPListTemplate` (Favourites + Categories, then a list of the category's
  channels), starts playback through `PlaybackManager` and hands the
  transport controls to `CPNowPlayingTemplate`. The window hijack, the
  `zPosition = 99999` lift and the 3-second "keep on top" timer are gone.
- **CarPlay channel rows request video.** On iOS 26.4+ each channel row
  carries a `CPPlaybackConfiguration` with a `.video` preferred presentation,
  which is how CarPlay is told the selection is video and the system presents
  the picture itself. The picker is a list rather than a grid for exactly this
  reason — only `CPListItem` carries that property, `CPGridButton` does not.
- **CarPlay search is reachable.** `CPSearchTemplate` is presented from a
  navigation-bar button on the root template.
- **The handset search box no longer shrinks the car catalogue.** The
  CarPlay browser reads the new `PlaylistStore.allGroups`, which is the
  unfiltered channel index.
- **The purchase layer is a real StoreKit 2 integration.** `StoreKitManager`
  loaded no products, bought nothing and hardcoded `isProUnlocked = true`. It
  now loads the products of the store, buys, restores, listens for
  `Transaction.updates` and reads `Transaction.currentEntitlements`. Nothing in
  the app is gated behind Pro — that is still a product decision — so the app
  behaves exactly as before.

### Removed

- A stale 56 KB Mach-O binary at the repository root, compiled from the
  deleted `CarTV/Tests/main.swift`. Nothing referenced it and it cannot run
  standalone.
- The CarPlay scene no longer assigns `CPWindow.rootViewController`,
  lifts a view above the template stack, or keeps it on top with a
  repeating timer. CarPlay owns that window.
