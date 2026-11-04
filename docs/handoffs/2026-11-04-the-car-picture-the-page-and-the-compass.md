# Handoff — the car's picture, the page that never arrived, and the compass (2026-11-04)

## The request

> *"video not automatic starting to car display and laggy and take time to start on the car display side need optimization on both side mobile and car display"*

> *"when i start youtube from car display so it start on mobile not on the ar display and when i try to type any think in serach bar so it crash the browser tab and redirect tom home screen"*

> *"the compase shows compoletely wrong direction on app"*

Three complaints, three root causes — and one of them was not where it looked.

---

## 1. The video did not start on the car's display

**Which "car"?** The first thing to settle was *which* car UI the user is
looking at. There are two:

- `CarPlaySceneDelegate` → `CPTabBarTemplate` — the **template** scene. This
  is what the **CarPlay Simulator** renders (proved by listing the windows
  with `CGWindowListCopyWindowInfo` and capturing the CarPlay window's id:
  the app grid and the tab bar, not a custom UI);
- `ExternalDisplaySceneDelegate` → `InCarAutomotiveController` — a plain
  `UIViewController` for a **real second screen**.

So the address bar of the car's browser is a `CPSearchTemplate` **pushed onto
the stack** — not the custom toolbar in `CarPlayVideoViewController`.

**The cause.** `PlaybackManager.play(channel:presentation:)` handed the
picture off under this guard:

```swift
if isCarConnected && presentation != .hidden { handOffToCar(offerImmediately: false) }
```

The **car** plays with `presentation: .hidden` (`CarPlaySceneDelegate.play`),
so the car's own play got **no ladder at all**. The picture was offered
exactly once, at the moment the row was tapped — and the car's video
endpoint registers up to **two minutes** after the scene connects, and the
system only looks at the AirPlay route when the picture is offered. That one
offer found no endpoint, and the car's screen stayed black.

The ladder itself was also wrong for the "laggy" part: it offered at 1 s and
3 s — right on the start — and every offer rebuilds the player and drops the
buffer, which is exactly the stutter.

**The fix.**

```swift
if isCarConnected { handOffToCar(offerImmediately: false) }
```

and the ladder repeats with growing gaps instead of a fixed pass:

```swift
private static let offerGaps: [TimeInterval] = [2.5, 2.5, 4, 7, 12, 20, 30]
```

The first gap is long enough for the video to start; the last one repeats,
because the endpoint can take two minutes to appear.

**AC139** (`PlaybackManagerTests`) — a video the car asked for is offered
again: the play is handed off at all, and the offer count grows.

## 2. The page opened on the car played on the phone

**The chain that is supposed to carry a page to the car** (and the SPEC's
non-goal says it plainly — CarPlay has no web view of its own):

    the car's search bar → the app's browser **on the phone** → the phone's
    screen share → the app's player → the car's AirPlay route

Two links in that chain were broken.

**First:** `playScreenShare` never handed the picture off. The share played
on the phone; the car's display stayed black even with a working broadcast.

```swift
if isCarConnected {
    phonePresentationMode = .hidden
    handOffToCar(offerImmediately: false)
}
```

**Second:** iOS always asks the **user** to start a share, and nobody was
asked. `startForTheCar()` armed the relay and nothing else, so the car sat
waiting for a broadcast that was never going to start. The phone now says so:

- `ScreenShareService.pendingCarPage` — the page the car asked for;
- `carRequestedPage(_:)` — arms the relay and sets the note;
- `InAppBrowserView` shows a banner with the **broadcast picker** while the
  car is waiting.

**AC140** — the share is handed off to the car. **AC142** — the phone is told
that the car is waiting.

## 3. The browser tab died and the app went back to the home screen

**What it is not:** the app did not crash. There is no crash report from the
user's session — the newest one is a FrontBoard **watchdog SIGKILL** of the
test host. A watchdog kill is an app that stopped answering, and the scene
restarts at its root: "redirect to home screen", with no crash log.

**The first loop:** `webViewWebContentProcessDidTerminate` reloaded the page
**unconditionally**:

```swift
public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.reload()          // the page that killed the process, loaded again
}
```

The page is loaded again, it kills the process again, and the app is taken
down with it. One reload is allowed now; a page that dies twice says so and
stops. The phone's browser tab (`BrowserTabItem`) had **no handler at all**,
so a dead page stayed dead — it now reloads once and then says "The page
crashed".

**The second loop:** the car's browser rebuilt its whole result list on
**every keystroke** — 17 rows, each with a picture at the car's scale. The
rows are built **once** now and only filtered afterwards (the same rule as
the Home tab's cards: a picture that is drawn is a picture that is paid for,
and the car tears the session down when the resource consumption reaches a
hundred per cent).

**AC141** — the same row object is handed over again, so the picture is not
drawn again.

## 4. The compass showed the wrong direction

Two separate mistakes, both visible in the app:

1. **The GPS course overwrote the compass.** `didUpdateLocations` wrote
   `location.course` into the heading on every fix. The course is the
   direction of *travel* — while the car is slow it is the GPS's noise, not a
   direction. The compass is the heading; the course is the fallback for a
   device without one. The last writer wins, so the noisy writer must not
   write last.
2. **The rose turned the wrong way.** A car heading east has north on its
   **left**, so the rose turns by **−heading**; a rose that turns *with* the
   heading points the opposite way. And the needle sat **inside** the rose,
   so it turned with it and always said north — the needle now sits outside
   the rose and stays fixed, and the rose turns under it.

The heading is also normalised into `0..<360`, and the cardinal direction
survives a negative heading.

**AC135–AC138** (`SatelliteHUDTests`) — the rose turns against the heading,
the compass wins over the course, the course is the fallback, and the
cardinal direction of a negative heading is right.

---

## What was not touched

- The **iPhone 18 Pro simulator** was never booted. Every build and every
  test ran on the physical iPhone 13 (`00008110-001C60423CB8401E`) through
  `scripts/device_test.sh`.
- `scripts/carplay_simulator.sh` was not run.
- The CarPlay **entitlements** and the provisioning profile were not changed.

## Where the code is

| What | Where |
|---|---|
| The hand-off ladder | `CarTV/Sources/Services/PlaybackManager.swift` |
| The share's hand-off | `PlaybackManager.playScreenShare(url:title:)` |
| "The car is waiting" | `CarTV/Sources/Services/ScreenShareService.swift` |
| The banner with the picker | `CarTV/Sources/Views/Browser/InAppBrowserView.swift` |
| The car's browser list | `CarTV/Sources/Views/CarMode/CarPlayTabs.swift` |
| The dead-web-process guard | `CarPlayVideoViewController+Browser.swift`, `BrowserTabManager.swift` |
| The compass | `CarTV/Sources/Services/SatelliteHUDService.swift`, `SatelliteHUDView.swift`, `DigitalClusterCardView.swift` |
| The tests | `CarTV/Tests/SatelliteHUDTests.swift`, `PlaybackManagerTests.swift`, `CarPlayTemplateTests.swift` |

## Still open

- **The broadcast itself is the user's tap.** iOS does not let the app start
  a share; the picker on the phone is the only way. The banner puts it in
  front of the user, but the share still has to be started by hand.
- **The CarPlay Simulator cannot host a session** in Xcode 27 — it attaches
  to physical devices only — so the picture was verified on the phone with
  the simulator's *screen*, not in a real car.
- The address bar of the **external display** scene still presents a
  `UIAlertController` with a text field. That is a different code path from
  the one the CarPlay Simulator shows, and it was left alone.
