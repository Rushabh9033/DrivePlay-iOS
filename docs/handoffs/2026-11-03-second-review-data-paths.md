# Handoff — 2026-11-03, the second review (the data paths)

## Where the work stands

The first review round is written up in
[`docs/review-2026-11-03.md`](../review-2026-11-03.md) (§1.1–§1.10) and in
[`2026-11-03-final-pass-repo-and-review.md`](2026-11-03-final-pass-repo-and-review.md).
It read the app's **architecture**.

This round read its **data paths** — the bytes that come in from a playlist, from a
server and from a device — and found twenty more bugs. They are fixed, they have a
test each (AC70–AC89), and they are written up in §1.11 of the review.

| Item | State |
|------|-------|
| **20 new bugs, fixed** | The parsers, the library, the two servers, the track picker, the car's rows and the phone's own behaviour. The list is in `docs/review-2026-11-03.md` §1.11. |
| **20 new tests** | `CarTV/Tests/ReviewRegressionTests.swift` — AC70 … AC89, one test each. |
| **The SPEC's trace** | **89 ACs → 89 test names**. The AC numbers in `docs/SPEC.md` and the AC numbers in `CarTV/Tests/` are the **same set** (checked mechanically). 103 `test_AC<n>_…` functions, 111 test functions in all. |
| **The device test build** | `xcodebuild -sdk iphoneos -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build-for-testing` → `** TEST BUILD SUCCEEDED **`. The 20 new tests compile for the phone. |
| **The simulator was not used** | Not booted, not installed to, not installed from. Every build was against a *generic* destination, which compiles without running anything. |
| **The new lessons** | Six new bullets in `AGENTS.md` under *"Gotchas from the second review (2026-11-03)"*. |
| **The CHANGELOG** | ~16 `Fixed` entries and 1 `Removed` entry under `[Unreleased]`. |

## The nine seams that made the bugs testable

None of the twenty was fixed by making the test weaker. Each one got a small,
honest seam instead:

| Seam | What it made testable |
|------|----------------------|
| `PlaylistStore.trimmedSearchQuery` | the trailing-space search (AC89) |
| `PlaylistStore.readChannels(fileData:legacyData:)` | one unreadable entry and the legacy blob (AC74, AC75) |
| `JellyfinClient.init(session:)` | the paging and the artwork token, with a stub server (AC76, AC77) |
| `PlexClient.preferredServer(in:)` | the account's own server vs. plex.tv (AC78) |
| `PlaybackManager` — `public private(set)` on the track names | a picker that wrote the name itself (AC79) — **a compile error now**, not a runtime test |
| `LocalMediaService(storageDirectory:)` | the failed copy and the temporary import, without touching the user's vault (AC86, AC87) |
| `AudioExtractorService.canStartExtraction` | the extractor that could be used only once (AC88) |
| `DeviceOrientationMonitor` | the orientation notifications that never came (AC85) |
| `ChannelListViewController` | the car picker that dropped the tail of a category (AC82) |

Two of the twenty could **not** be made testable, and the reasons are in
`AGENTS.md`:

- **`AVMediaSelectionGroup` only exists for assets with alternate renditions.**
  Measured on macOS: a WAV's `loadMediaSelectionGroup(for: .audible)` is `nil`,
  and so is an `AVMutableComposition`'s. `item.select(_:in:)` therefore cannot be
  exercised in a unit test without a server that serves HLS with alternate audio
  renditions. The fix is pinned by the read-only contract instead.
- **The relay's over-long announcement** *is* observable, and was measured on
  macOS first: the client sees `failed(POSIXErrorCode 54: Connection reset by
  peer)` when the server drops the peer. That measurement shaped AC84 exactly.

## Still blocked on hardware — the phone

The physical iPhone 13 (`00008110-001C60423CB8401E`) left the USB bus mid-session
and has not come back (`xcrun devicectl list devices` reports it `unavailable`).
Two things need it:

1. **The device test suite** — `scripts/device_test.sh`. The fixes for AC34
   (the capture seam) and AC47 (the loopback blocker) and the 20 new tests
   (AC70–AC89) all compile for the device, but have not been *run* on it. The
   background job `/tmp/after_phone2.sh` is still waiting for the phone; **do not
   start a second one.**
2. **The photographs of the car's screen** — the four tabs and the picture on the
   car. Xcode 27's CarPlay Simulator hosts **physical devices only**.

The phone has to be plugged in **and unlocked**: a locked device shows as
`unavailable` and cannot be driven.

## The question the user asked, and the answer

*"new UI done ?? same as i mentioned ?"* — with the two reference screenshots
(a **"▶ 📺 Play on Car Display"** pill over the video, and a **"Car connected"**
banner with **"Play on Phone"** and **Pause**).

**The code is done and it is exactly those two things:**

- `CarOutputSwitch` puts the *"▶ 📺 Play on Car Display"* pill over the video —
  the whole pill is the system's route picker — and the *"Car connected"* banner
  with *"Play on Phone"* and a pause button. The picture travels the AirPlay
  route; the system reports the route back (`isExternalPlaybackActive` → KVO →
  `PlaybackManager.isPlayingOnCar`).
- The **four CarPlay tabs** (Home, Favorites, Cast, Browser) are a
  `CPTabBarTemplate` of four `CPListTemplate`s. CarPlay renders **templates
  only** — the **system** paints the tab bar, the selection marker and the list
  chrome, so the dark segmented appearance with the green indicator is the
  system's own drawing. The app can only supply the titles, the icons (drawn in
  the app's green accent) and the artwork (drawn at the car's display scale).

**The photographs are the one thing that is still missing**, and they need the
phone and a car. Everything above is implemented, compiles for the device and is
described in `docs/review-2026-11-03.md` §2.

## What was **not** changed, and why

- **`UIBackgroundModes: audio` was not touched.** It normally wants
  `com.apple.developer.avfoundation.multitasking`, which the CarPlay
  entitlements files do not carry. Changing the entitlements risks the signing
  chain, so it is **reported**, not changed (review §4.6).
- **No new dependency** was added — nothing here needed one.
- **`CarPlayAutomotiveDashboardView` was deleted** (822 lines) rather than
  rewritten: it was a second, never-presented implementation of the car's
  screens — a second source of truth for the same shelves, the same artwork and
  the same tab state. `xcodegen generate` after the deletion, or the build fails
  with *"Build input file cannot be found"*.

## If the phone does not come back

The build, the tests (they compile) and the docs are all in place; what is
missing is the *run* on the device and the picture of the car's screen. The
suite is one command away:

```bash
scripts/device_test.sh          # waits for the phone, then runs the suite
```
