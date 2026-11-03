# Handoff — 2026-11-02 — Screen-share broadcast: the player had nowhere to draw

## What was asked

Real working broadcasting of the phone's screen to a car's display — the
WhatsApp-video-call style screen share — CarPlay Simulator acceptable for now.

## What the chain looks like now

```
ReplayKit capture → H.264 fragments (AVAssetWriter, .mpeg4AppleHLS)
                  → a local HTTP server (token in the path)
                  → the app's own AVPlayer
                  → the car's now-playing area
```

A car screen never shows a mirror, only the video the app plays. So the app
records its screen, serves it as a live HLS playlist and plays that very
stream. The same playlist is served on the local network, so a head unit that
is not CarPlay can open it.

- `CarTV/Sources/Services/ScreenShareService.swift` — `LiveScreenWriter`
  (the encoder), `ScreenStreamServer` (the HTTP server), `DemoFrameSource`
  (the drawn picture the CarPlay Simulator can use), `ScreenShareService`
  (the app-facing state machine).
- `CarTV/Sources/App/CarPlaySceneDelegate.swift` — the CarPlay row that starts
  the share.
- `CarTV/Sources/Views/Cast/CastToCarView.swift` — the share card on the phone.

## The bug that cost the session (and was not where it looked)

**The stream was never broken.** The player downloaded the playlist, the
initialisation segment and every fragment, and still sat at `currentTime() == 0`
with `timeControlStatus == .waiting`.

CoreMedia's own log said why:

```
indicate ready to start, because video-only item is waiting for video output
```

**A video-only `AVPlayerItem` never renders without a video output.** With no
`AVPlayerLayer` attached there is no renderer, so the playhead never leaves
zero — no error, no failure status, the item even reports `.readyToPlay`.
Every probe that used a bare `AVPlayer` measured the same false negative.

The proof: attach an `AVPlayerLayer` and the *same* stream plays —

```
status=1 tcs=2 t=0.84 waitReason=nil
status=1 tcs=2 t=1.85 waitReason=nil
status=1 tcs=2 t=2.86 waitReason=nil
...
status=1 tcs=2 t=8.46 waitReason=nil
```

The app's player view already attaches a layer, so the app was never affected.
Only the test was. AC32 now attaches one and asserts the picture advances.

### Two measurement traps that cost time

- **The macOS command line cannot render HLS at all.** Every stream — Apple's
  own included — reports `status=1, tcs=1, t=0.0` there, while the Simulator
  plays them. Do not debug HLS on the command line.
- **A video-only item with no layer is the same symptom.** Check
  `player.reasonForWaitingToPlay` and the CoreMedia log before suspecting the
  media.

## What changed

| File | Change |
|------|--------|
| `CarTV/Tests/ScreenShareTests.swift` | AC32 attaches an `AVPlayerLayer` and asserts the playhead advances. The `print("PROBE …")` is gone. |
| `CarTV/Tests/CarPlayTemplateTests.swift` | AC33: the screen-share row asks CarPlay for the video surface. |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | The share moved from a `CPBarButton` to a `CPListItem` with `CPPlaybackConfiguration(preferredPresentation: .video)`. Only `CPListItem` carries that property, and it is how CarPlay is told the selection is video — the bar button left the car's now-playing area with no picture to draw. |
| `CarTV/Sources/Services/ScreenShareService.swift` | The temporary request-log line is gone. |
| `AGENTS.md` | Three new gotchas (the video-output one, the command-line HLS one, the 503 one) and the correction of the `RPScreenRecorder.isAvailable` rule, which is **not** always `false` on the Simulator — it is `true`, and the capture delivers no frames. |
| `docs/SPEC.md` | AC29–AC33. |
| `CHANGELOG.md` | The screen-share feature, the CarPlay row, the test count (55). |

## Verification

```bash
./scripts/run_tests.sh     # 56 tests, 0 failures
```

The chain was also checked end to end in the Simulator: the server's request
log shows the textbook order (playlist → init → fragment → playlist → next
fragment …) and the playhead advances at 1×.

## What is left — and what only the user can do

1. **Apple granted the CarPlay Video entitlement** (Case-ID 23260500, team
   47T499AR2T). The app's entitlements file was already right — it asks for
   `com.apple.developer.carplay-video` only, and Apple's mail is explicit that
   audio and video in one app are not supported.
   **One portal step is left, and it is manual:** the App ID
   `XC com rushabh cartvv` still carries the **CarPlay Audio App** capability,
   so the profile cannot carry video. In developer.apple.com → Identifiers →
   App IDs → `XC com rushabh cartvv` → Capabilities: turn **CarPlay Audio App**
   off, turn **CarPlay Video App** on, Save. Then
   `scripts/carplay_grant.sh grant <udid>` makes Xcode fetch a profile that
   carries it, and the device build signs again.
2. **The picture on the car's screen** can only be checked in the CarPlay
   Simulator once the CarPlay scene is attached to the booted Simulator (a
   one-click Device Hub action — there is no CLI for it). Then: open the car
   app, tap **Screen Mirroring**, and the picture appears in the now-playing
   area.
3. On the Simulator the share row used to die with *"This device cannot record
   the screen."* Now a capture that delivers no frame hands over to the demo
   picture by itself (AC34), so the row works on the Simulator. Measured:
   `RPScreenRecorder.isAvailable` is `true` there, but the capture ends again
   within a second without a frame.

## Why "our app is not on simulator" (measured 2026-11-02 13:05)

The CarPlay Simulator window was bound to the **physical iPhone 13**, not to the
iPhone 18 Pro Simulator:

```
CarPlay Simulator - Rushabh’s Iphone, Untitled       ← window title
Sessions ▸ Rushabh’s Iphone                            ← the only session
devicectl: 00008110-001C60423CB8401E  iPhone 13   physical   connected
```

So the car screen listed CarTV because the app **is** installed on that 13 — but
the copy on the 13 is the interim build that had to be signed with
`CODE_SIGN_ENTITLEMENTS=""` (the portal had no video capability yet), so CarPlay
cannot launch it. The icon is there, the app cannot start.

The iPhone 18 Pro Simulator — where the app is installed and where CarPlay needs
no entitlement at all — was **not** attached. That is why the simulator's log
holds **zero** `carTemplateApplication` role launches in 90 minutes, and only
`UIWindowSceneSessionRoleApplication` ones.

**The standalone CarPlay Simulator app pairs with physical devices only**: its
binary links CoreDevice and MobileDevice (`attachSession:callbacks:target:queue:`,
`Failed to attach device with CoreDevice`) and contains no CoreSimulator path.
Its `Sessions` menu therefore lists connected iPhones only. Pairing a *simulated*
device is an Xcode 27 **Device Hub** action (no CLI, no menu entry — Xcode 27 has
no `Window ▸ Devices`; see WWDC26 session 212).


- Does the CarPlay now-playing area draw the screen-share stream once the
  entitlement exists, or does the share need its own `CPNowPlayingTemplate`
  configuration? The row now carries the same video signal the channel rows
  carry, which is the sanctioned mechanism, but it has never been seen drawing.
- The stream is served on the loopback interface and on the local network. A
  head unit that is not CarPlay (Android Auto, DLNA) is **not** covered — that
  is a separate feature, and it needs a decision about discovery (mDNS) and
  about how the phone's screen is captured on a device where the app is in the
  background.
