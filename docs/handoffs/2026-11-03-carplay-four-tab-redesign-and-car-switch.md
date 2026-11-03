# Handoff — the car's four tabs, the car/phone switch, and the black-display fix (2026-11-03)

Follows `2026-11-03-carplay-verified-on-the-car.md` (the template path verified on
the car) and `2026-11-03-carplay-video-flip-in-the-portal.md` (the profile now
carries the video entitlement).

## 1. What changed

### The car's screen is a tab bar with four tabs

`CarPlay/Sources/App/CarPlaySceneDelegate.swift` now builds a
`CPTabBarTemplate` with **Home, Favorites, Cast and Browser**
(`CarPlayTab`, `CarPlay/Sources/Views/CarMode/CarPlayTabs.swift`). Every tab is a
`CPListTemplate`:

- **Home** — the whole playlist under "All" with its real count, then every
  category, each with its own count, its own artwork, its channels as a
  horizontally scrollable row of cards (`CPListImageRowItem`, iOS 26+) and a
  *Show all N channels* row that opens the whole category.
- **Favorites** — `PlaylistStore.favoriteChannels`, the phone's own list. The
  store's `@Published channels` drives the refresh, so a favourite toggled on
  the phone is on the car at once.
- **Cast** — the real state of the player and of the broadcast: where the
  picture is, whether it plays, what the share does, and the two actions each
  one allows.
- **Browser** — the sites of the app's own `BrowserCatalog`, opened **on the
  phone**. CarPlay has no web view (Apple does not allow one), so this is the
  closest compliant interaction: the phone's browser shows the page and the
  screen share carries the picture to the car.

Every row that stands for video carries a `CPPlaybackConfiguration`
(`preferredPresentation: .video` when the build is entitled, `.audio`
otherwise) — that is the signal that makes the system draw the picture itself.

### The design system the artwork carries

`CarPlay/Sources/Views/CarMode/CarPlayArtwork.swift` — `CarPlayPalette` (charcoal
tile, green accent, white type), a 32 MB `NSCache` of logos, and a logo drawn
with `AVMakeRect(aspectRatio:insideRect:)` on a rounded card: **never
stretched, never clipped**. A logo is fetched once, however often the screen is
rebuilt.

Two things make it fit the car rather than the phone:

- **The car's display scale.** Apple says it plainly: *"images you display in
  any template should be sized to a display scale matching the scale of the
  `carTraitCollection`, not the scale of the iOS device's main screen."* The
  scene sets `CarPlayArtwork.displayScale` from
  `interfaceController.carTraitCollection.displayScale` when it connects.
- **The drawn tiles are cached too.** The screen is rebuilt whenever a
  favourite is toggled or a logo arrives; with thousands of channels, drawing
  every card again is a stall, so the drawn card is cached by
  channel + size + scale + whether the logo is in yet.

### The switch between the car and the phone

`CarTV/Sources/Views/Player/CarOutputSwitch.swift` — a "▶ 📺 Play on Car Display"
pill over the video (the whole pill is the system's route picker) and a
"Car connected" banner with "Play on Phone" and a pause button.

The car's display is an AirPlay destination, so the picture travels the AirPlay
route: the player offers the video to the car's display
(`allowsExternalPlayback`), the system reports the route back
(`isExternalPlaybackActive`, KVO → `PlaybackManager.isPlayingOnCar`).

### The black car's display — the root cause

A **video-only `AVPlayerItem` never renders without a video output**: CoreMedia
logs *"video-only item is waiting for video output"*, `timeControlStatus` stays
`.waiting` and the playhead never leaves zero — while the stream itself is
perfectly fine. On the car the phone shows no player at all (`MainTabView`
builds `DockedPlayerContainerView` only in `.docked` mode), so **nothing owned an
`AVPlayerLayer`** and the item never started.

`CarTV/Sources/Services/VideoOutputHost.swift` gives the player a small output
of its own whenever the phone shows no picture, and gives it up again the moment
the phone's own player comes back — one output at a time.

### The picture survives the phone being minimised or locked

`audiovisualBackgroundPlaybackPolicy = .continuesIfPossible` (with the `audio`
background mode) and a `scenePhase` hook in `CarTVApp` that calls
`keepPlayingInTheBackground()` when the phone goes to the background.

### The broadcast reaches the car

The relay only listened after a CarPlay row was tapped or the phone's screen
mirroring tab appeared — but the user starts a broadcast from the **Control
Center**, so the extension announced its stream into a relay that was not there
yet. The relay now starts in
`application(_:didFinishLaunchingWithOptions:)`.

## 2. Build

```bash
xcodegen generate
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphoneos \
  -destination 'generic/platform=iOS' -configuration Debug \
  CARPLAY_CATEGORY=video build-for-testing
→ ** TEST BUILD SUCCEEDED **
```

The built app carries both CarPlay entitlements:

```
$ codesign -d --entitlements :- CarTV.app
  "com.apple.developer.carplay-audio" => true
  "com.apple.developer.carplay-video" => true
  "application-identifier" => "47T499AR2T.com.rushabh.cartvv"
```

## 3. Tests

New: `PlaybackManagerTests` AC51–AC54 and AC64; `CarPlayTabTests` AC55–AC61;
`CarPlayArtworkTests` AC62–AC63, AC65–AC66. `docs/SPEC.md` carries the criteria.

**Simulator (2026-11-03, 13:59):** `scripts/run_tests.sh` →
`Executed 90 tests, with 2 tests skipped and 0 failures (0 unexpected) in 29.451 seconds`.
The two skipped are `VoiceSearchTests` (AC67/AC68) — they need the microphone
permission, which the Simulator does not grant.

The suite runs **on the phone** — Xcode 27's CarPlay Simulator hosts physical
devices only, and the video surface and the broadcast can only be exercised
there:

```bash
scripts/device_test.sh     # waits for the phone, then runs the suite on it
```

`CarTVTests` had **no development team**, so `xcodebuild test` against the phone
failed with *"Signing for CarTVTests requires a development team"*. It is signed
like any other app now (`project.yml`).

## 4. Still open

* **`xcodebuild` does not return after the Simulator run.** The tests themselves
  finish and report green (*"Executed 88 tests, with 0 failures"*), the app
  process exits, and then `xcodebuild` sits in
  `waitForBuildWithBuildLog:` instead of printing `** TEST SUCCEEDED **` and
  exiting — it has to be killed (exit 143). The hang is in the tool, not in the
  app: the app is gone from the simulator's process list by then. It was seen
  before this milestone as well.
* **The phone was off USB** while this ran, so the suite and the car run
  themselves are **not** verified — `scripts/device_test.sh` waits for it and
  runs the tests the moment it shows up. Everything above is a *build* result.
* **`CPSearchTemplate` on a video CarPlay app** — Apple's category/template
  matrix lists search for navigation and parking, and the audio/video rows have
  varied between releases. The presentation carries a completion handler, so an
  unsupported template logs a failure instead of throwing (CarPlay throws an
  `NSException` only when a call fails **and** no handler was given). If search
  does nothing on the car, the compliant fallback is a `CPListTemplate` of the
  matching channels.
* **`RPBroadcastSampleHandler` is "no longer supported" in iOS 27.** The picker
  still works; the upload extension may not launch at all. The whole-phone
  mirroring fallback is the system's own AirPlay screen-mirroring route.
* `git init` + a first commit — the project is **not** a git repository.
* `docs/handoffs/2026-11-03-carplay-video-flip-in-the-portal.md` still describes
  the profile as lacking the video entitlement; it carries both now.
