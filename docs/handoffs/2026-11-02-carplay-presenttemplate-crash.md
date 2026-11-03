# Handoff — tapping any row on the car crashes the app (2026-11-02)

> **Fixed on 2026-11-03** — see `2026-11-03-carplay-presenttemplate-crash-fix.md`.
> **The root cause below is wrong**: it blames presenting a template from inside the
> item handler. The real cause is that `presentTemplate` does not accept a
> now-playing template, and a failed presentation with **no completion handler**
> throws an `NSException`. The fix is not in this document.

**Status: open, not fixed.** The user hit it independently ("when I click any
playlist video so app crash"); this session reproduced it with a crash log.
Fix it tomorrow.

## 1. The bug

Tapping **any row in the CarPlay list template** — a channel, a category, the
"Screen Mirroring" row — kills the app. The car display falls back to the app
grid and the app is gone.

Reproduced on the physical iPhone 13 (iOS 27.0, `00008110-001C60423CB8401E`),
app pid 10605, build installed with `scripts/auto_install.sh`. The crash log
is on the device and can be pulled again with:

```bash
xcrun devicectl device copy from --device 00008110-001C60423CB8401E \
  --domain-type systemCrashLogs --source CarTV-2026-11-02-181816.ips \
  --destination /tmp/crashdump/CarTV-181816.ips
```

### The crash, exactly

```
exception  EXC_CRASH / SIGABRT   "abort() called"   byProc: CarTV

+[NSException raise:format:]
-[CPInterfaceController presentTemplate:animated:completion:]
CarPlaySceneDelegate.presentNowPlaying()
CarPlaySceneDelegate.play(channel:)
closure #1 in static CarPlaySceneDelegate.makeChannelItem(_:owner:prefersVideo:)
thunk for @escaping @callee_guaranteed (CPSelectableListItem, () -> ()) -> ()
__95-[CPListTemplate listTemplateWithIdentifier:didSelectListItemWithIdentifier:completionHandler:]_block_invoke
```

The exception **reason string is not in the `.ips`** — only the backtrace is.
So the exact message has to be confirmed at runtime; the frame is not in
doubt.

## 2. Root cause

`CarTV/Sources/App/CarPlaySceneDelegate.swift:276`

```swift
private func presentNowPlaying() {
    guard let interfaceController else { return }
    let nowPlaying = CPNowPlayingTemplate.shared
    nowPlaying.updateNowPlayingButtons([])
    interfaceController.presentTemplate(nowPlaying, animated: true, completion: nil)
}
```

`presentNowPlaying()` is called **from inside the `CPListItem` handler** —
i.e. while CarPlay is still processing the selection. `presentTemplate` is
not allowed there: the interface controller is mid-transition and raises an
`NSException`, which is an uncaught ObjC exception, so the process aborts.
Swift's `try` cannot catch it, and `presentNowPlaying()` is not wrapped in
anything that could.

**Scope: both rows.** `play(channel:)` (channel rows) and `startScreenShare()`
(the "Screen Mirroring" row) both end in `presentNowPlaying()`, so the Screen
Mirroring row crashes the same way — it just was never reached, because the
sibling row crashes first.

The unit tests do not catch it: `makeRootSections`/`makeChannelItem` are
testable without a scene, but `presentNowPlaying()` needs a live
`CPInterfaceController`, which cannot be created outside a connected CarPlay
scene. That is why the template tests are green while the car is not.

### Fix sketch (for tomorrow — verify before shipping)

Present the template **after the handler returns**, not inside it:

```swift
item.handler = { _, completion in
    owner?.play(channel: channel)
    completion()          // the selection is done first
}
```

and in `presentNowPlaying()`, hand the presentation to the next runloop turn
(`DispatchQueue.main.async`) so the interface controller is idle. Confirm the
real reason string first — if it is not "a presentation is already in
progress", the fix is different.

**Regression test (AC45):** the car template must not present a template from
inside an item handler — assert that the handler returns before any
presentation is scheduled (e.g. a fake/recording `CPInterfaceController`
protocol), so the shape of the bug is locked down even though the real
controller cannot be built in a test.

## 3. What was tested, and what could not be

| Check | Result |
|-------|--------|
| CarPlay Simulator attached to the car | ✅ it is attached to the **physical iPhone 13** |
| The DrivePlay CarPlay template renders on the car | ✅ root template, "Screen Mirroring", Categories, channel counts |
| Tapping a row | ❌ **the app crashes** (above) |
| The Screen Mirroring row | ⛔ not reached — the sibling row crashes first |
| A picture in the car's now-playing area | ⛔ still blocked on Apple's CarPlay Video grant (`docs/carplay-video-request.md`) — the device build is the audio category, so CarPlay refuses a video presentation |

## 4. How the CarPlay Simulator is driven (measured, saves an hour)

* **The CarPlay Simulator in Xcode 27 attaches to physical devices only.**
  Its binary has `USBiPhoneDevice` / `AMDeviceConnect` paths and **no**
  `SimDevice`/`CoreSimulator` reference; `DeviceHub.app` has **zero** CarPlay
  strings; the app's "Sessions" menu lists only the physical iPhone; and the
  simulator's `runningboardd` logs *"Error 1 setting Carplay mode to 0:
  Operation not permitted"* for the app. **An iOS Simulator device cannot host
  a CarPlay session** — so the demo picture on the Simulator (and
  `scripts/carplay_simulator.sh`) cannot be seen on a car any more.
* **A System Events `click at` does not reach the car's display.** The
  display has no accessibility elements at all (the AX tree holds one static
  text), and a synthetic click is ignored. A **Quartz `CGEvent`** (move →
  leftMouseDown → 150 ms → leftMouseUp) does work.
* **Getting the app onto the car:** launch it *and* select it in the car's app
  grid. `devicectl device process launch` needs `--activate` to bring it to
  the foreground, and the app still has to be picked in the grid (the grid
  shows the phone's home screen, tap the DrivePlay icon).
* **Reading the car's pixels:** `screencapture` the whole screen and crop the
  CarPlay Simulator window; the row positions are in the *screenshot's* pixel
  space, not the window's.

## 5. Still open

* **The crash above** — the priority for tomorrow.
* **The phone was left with the app not running** (it crashed). It could not
  be relaunched at the end of the session: the device went `unavailable` on
  the host, so `devicectl` refuses the launch. Tap DrivePlay on the phone
  itself — it opens fine; it is the *rows on the car* that crash.
* **Apple's CarPlay Video grant** — one click by the account admin
  (`docs/carplay-video-request.md`). Until then the device build signs with
  the audio category and the car shows the now-playing screen, never a
  picture.
* **Whether iOS 27 still launches the broadcast upload extension** — one tap by
  the user on the phone: DrivePlay → Screen Mirroring → the broadcast button →
  "DrivePlay Screen Relay".

## 6. Verification

```bash
./scripts/run_tests.sh     # 66 tests, 0 failures — and they do NOT cover this
```

The suite is green with the bug in place: the crash needs a live CarPlay
scene, and `CPInterfaceController` cannot be created in a test.
