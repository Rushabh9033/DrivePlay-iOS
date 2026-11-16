# Session: 2026-11-05 — the offline vault on the car's display

## Goal
- The user's complaint: *"off line video not visible on simulator side"*. The
  **online** channels reach the car; the **offline vault** did not.
- The standing goal is still the car's own browser running **on** the car's
  display, and every playlist on the car.

## Branch / state
`main` — dirty (no git repository in this checkout)

## Done
- **The root cause of the vault's failure on the car**: `-11870`
  (`AVErrorExternalPlaybackNotSupportedForAsset`) fires the instant the car's
  external route goes active, and it kills the item for good. The vault handed
  the player a `file://` URL **inside the app's container**, and the car's
  display is fed by the system's own video target — a process that runs
  **outside** the sandbox and cannot open a sandboxed file. The browser's
  picture never had the problem: it is served over HTTP.
- **The fix**: `CarTV/Sources/Services/VaultFileServer.swift` serves one vault
  file over HTTP (a **256-bit** token — 32 bytes of `SecRandomCopyBytes`, in
  hex, compared in constant time — in the path, `Accept-Ranges: bytes`, real
  `206` answers), bound to the **loopback** only — the user's own media stays
  on the phone and no local-network permission is needed.
  `PlaybackManager.play(channel:)` serves a file URL and hands the **player**
  the served URL, while the watch history keeps the **file** (the served URL
  dies with the server). The server goes when the file is not played any more.
  The serving lives in `play(channel:)` — the **one way in** — because the
  history's *"watch again"* row is a caller like every other: a fix in a
  method of its own would have left that row handing the player a `file://`
  URL, and the video would have died on the car the second time it was
  played.
- **The re-offer ladder no longer restarts the clip**: re-attaching an item
  that is already playing resets it to zero, and the seek that followed was
  thrown away with it. The offer brings a **new** item for the same asset, and
  the new item is watched too (the observers belong to the item).
- **AC176** — written: the vault's video is served over HTTP, the **player**
  is given that URL, the bytes come back as they are on disk and a range
  request gets the slice that was asked for. It runs on the phone — the run
  is below.
- The compile check: **`TEST BUILD SUCCEEDED`** on `generic/platform=iOS`
  (`CARPLAY_CATEGORY=video`) — after the restructure too, with no warning.
- The **server itself** checked on the Mac, without the phone:
  `scripts/vault_server_check.sh` compiles the real
  `VaultFileServer.swift` for macOS and answers over HTTP — `200` with the
  file's bytes and `Accept-Ranges`, the token 64 hex characters, `206` with
  the right slice for `bytes=100-199` and `bytes=4000-`, the `Content-Range`
  announced, `404` without the token and `404` with a **wrong** token —
  **ALL GREEN**. The XCTest needs the phone; this one does not, so the fix is
  provable while the phone is away.

## In progress
- The **device run** of `OfflineVaultPlaybackTests` + `CarPlayTemplateTests`.
  The phone (`00008110-001C60423CB8401E`) is off the USB bus and out of
  Wi-Fi range: `devicectl device info lockState` answers *"not able to
  fulfill the requested usage assertion requirements"* (`CoreDeviceError
  4016`) with an **empty** `CurrentlyAssertableStates`, and the phone is not
  in `xcodebuild -showdestinations`. A waiter is running.
- The **last mile**: the picture on the car's own display, through the CarPlay
  Simulator with the phone attached. The chain is proven to the last public
  API the app owns (`AVPlayer` with `allowsExternalPlayback`); what the system
  does with it on the car's screen is the simulator's part, and the simulator
  needs the phone on the cable.

## Blocked
- Nothing in the code. The phone has to come back (cable or Wi-Fi) for the
  device run, and the CarPlay Simulator in Xcode 27 attaches to physical
  devices over USB only, so the manual check needs the cable.
- The CarPlay scene only connects when **DrivePlay is open on the car's
  screen** — the car opens it, not the app. The car display is never clicked
  from here.

## Files touched
- `CarTV/Sources/Services/VaultFileServer.swift` (new)
- `CarTV/Sources/Services/PlaybackManager.swift`
- `CarTV/Tests/OfflineVaultPlaybackTests.swift`
- `scripts/vault_server_check.sh` (new) — the server's own check, no phone needed
- `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md`
- `docs/handoffs/2026-11-05-the-vault-on-the-car.md` (new)

## Decisions made
- The vault's file is **always** served over HTTP, not only when a car is
  connected: `allowsExternalPlayback` is on for every channel, so **any**
  AirPlay route (the car's, or a screen at home) takes the item, and a
  `file://` asset dies the moment it does.
- The server is bound to the **loopback**: the car's video target runs on the
  phone, and a listener on every interface asks the phone for the
  local-network permission and puts the user's own media on the network.
- The watch history keeps the **file**, not the served URL — a "watch again"
  row must not point at a port that is gone.

## Next
1. The device run: `OfflineVaultPlaybackTests` (AC170, AC172, AC176) and
   `CarPlayTemplateTests` (AC175) on the physical iPhone 13, phone unlocked.
2. The vault's video on the car's own display, with DrivePlay open in the
   CarPlay Simulator.
3. The whole suite on the phone (`scripts/device_test.sh`).
