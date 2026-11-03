# Handoff — the CarPlay Simulator draws the picture (2026-11-02)

## 1. What this session settled

**The live screen-share chain was never broken — the test that measured it was.**

AC32 ("the player's video output plays the stream the app serves") had failed for a
whole session. The investigation measured the encoder, the fMP4 packaging, the
playlist, the HTTP server and the token gate — and exonerated all of them:

* Apple's **own** known-good fMP4 HLS stream behaved exactly like ours
  (`status=1`, `tcs=1`, `t=0.0`) in the same probe, while the same URL plays in
  the Simulator. So "fMP4 HLS is broken on macOS 27" was a **false negative**,
  not a finding.
* The reason is in `AGENTS.md` and was written down here: a video-only
  `AVPlayerItem` **never renders without a video output**. With no
  `AVPlayerLayer` attached, CoreMedia logs *"video-only item is waiting for
  video output"*, the playhead never leaves zero and `timeControlStatus` stays
  `.waiting` — while the segment pump keeps downloading every fragment. The
  player was fine; it had nowhere to draw.

Two traps cost the session time and are now in `AGENTS.md`:

* **The macOS command line cannot render HLS.** Every stream reports
  `status=1, tcs=1, t=0.0` there, Apple's own included. Do not debug an HLS
  problem on the command line.
* **A probe that blocks the main thread never loads an asset at all.** AVFoundation
  loads on the main run loop; `Thread.sleep` on the main thread stops it dead
  (the probe then shows *zero* requests, which looks like a server bug).

The stream itself was already correct: the app never hands the player a URL
before the writer has a playlist (`ScreenShareService.publish` waits for it),
because **AVFoundation fails a player item permanently on an HTTP 503** — there
is no retry.

## 2. What changed

| File | Change |
|------|--------|
| `Shared/LiveScreenStream.swift` | **The app could die when the capture delivered no frame.** The encoder starts with the first frame, so a capture that delivers nothing leaves a writer that was never started — and `finishWriting` on such a writer throws `NSInternalInconsistencyException`, which terminates the app. That is the normal path on the Simulator, and the path a phone with CarPlay connected takes (`-5813`). The writer is now only closed when it actually started; `finish()` takes an optional completion so a caller can wait for it. |
| `CarTV/Sources/Services/ScreenShareService.swift` | New `startForTheCar()`: what the car's row asks for. It waits for a broadcast, and on the **Simulator** it starts the demo picture as well (`startsDemoInsteadOfBroadcast`, a build-time fact — `#if targetEnvironment(simulator)`, never a run-time guess). |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | The "Screen Mirroring" row calls `startForTheCar()`, and its detail text tells the truth on both platforms. |
| `CarTV/Tests/ScreenShareTests.swift` | **AC41**: the row starts the demo on the Simulator and waits for the broadcast on a device. **AC42**: the encoder can be closed without a single frame. AC40 now stops the relay it started, so the fixed relay port is free for the next test. |
| `scripts/carplay_simulator.sh` (new) | Builds and installs the app in the Simulator **with the CarPlay video entitlement** and prints the two facts that decide it. |
| `docs/SPEC.md` | AC35–AC42 rows — the tests for AC35–AC40 existed, the rows did not. |
| `CHANGELOG.md`, `AGENTS.md` | The Simulator/entitlement gotchas, the crash, and the new behaviour. |

## 3. How to see it in the CarPlay Simulator

The Simulator does **not** need Apple's grant: the entitlement lives in the
app's Mach-O, and the Simulator never checks it against a profile. The device
build is the opposite — without the granted capability it does not sign — so
the default stays `"audio"`.

```bash
scripts/carplay_simulator.sh          # build + install + launch, category=video
```

Then attach the CarPlay Simulator in Xcode's **Device Hub** (a one-click action;
there is no CLI for it) and tap **Screen Mirroring** on the car: the demo
picture travels the same chain as a real share — capture → encode → serve →
play — and the car draws it in the now-playing area.

The playlist is served on the local network as well, so a head unit that is not
CarPlay can open `http://<phone-ip>:<port>/<token>/live.m3u8` and watch the
stream live.

## 4. Still open

* **Apple's grant** — one click by the account admin (Identifiers → App ID →
  Capabilities → CarPlay Video on, CarPlay Audio off). Until then the **device**
  build signs with the audio category and the car keeps working as it does
  today. See `docs/carplay-video-request.md`.
* **The broadcast on a real phone.** iOS 27 deprecates the whole ReplayKit
  broadcast family ("No longer supported"), and `ScreenCaptureKit` — the
  successor — is **app-only capture on iOS**, so it cannot mirror other apps.
  Whether the `ScreenRelay` extension is still launched has to be tried on the
  device. If it is not, the phone's screen cannot be mirrored to the car on
  iOS 27 — the app's own *content* on the car's video surface still can.
* **No device test.** The relay is verified by unit tests (AC37–AC40) and the
  chain by AC32; the broadcast → car path has not run on hardware.

## 5. Verification

```bash
./scripts/run_tests.sh     # 66 tests, 0 failures
```

* AC29–AC32: the server serves the live stream, the demo feeds the same
  encoder, and **the app's own `AVPlayer` plays the stream the app serves** —
  with an `AVPlayerLayer` in a `UIWindow`, exactly as the app's player view
  does.
* AC41: the car's row starts the demo on the Simulator.
* AC42: the encoder closes without a frame, without killing the app.

**The crash was a race**, and that is why it survived: the Simulator sometimes
delivers a single frame before it stops, and a writer that received one frame
*can* be finished. One test run passed, the next crashed the host — and
xcodebuild re-ran the suite, so the "green" result was the retry. The suite
must be read for `Terminating app`, not only for the exit code.
