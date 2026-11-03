# Handoff — the picture on the car's display, and the car's own browser (2026-11-03)

## The three defects this pass answers

1. *"not playing now … and still where is images of the playlist"* — the car's
   display stayed **black**: the now-playing bar appeared, the video did not.
2. *"when i click on play on car so don't show option and direct instant start
   video on car display"* — the button opened the system's **route picker**
   instead of going straight to the car.
3. *"i want proper browser fill with header should be search url bar … and the
   browser added that not working any more"* — the Browser tab was a list of
   sites whose rows did **nothing**, and it had no address bar.

## What was wrong, and what was done

### 1. The black car's display — the picture was offered, never handed over

The AirPlay route belongs to the system, and the system **only looks at it when
the picture is offered** (`airplayRoute_updateRouteInformation … Local
Playback = 1` in the device log). The offer that happened before the car's
video endpoint existed found no endpoint, and nothing made the system look
again — so the picture stayed on the phone while the car showed black.

`PlaybackManager.handOffToCar()` now offers the picture to the car **at once**
and **again** after 3 s, 8 s and 20 s, each time guarded by "a car is
connected" and "the system has not already reported the picture on the car".
The offer is `replaceCurrentItem(with:)` — the trick `castToPhone()` already
used — because it makes the system build a new player and look at the route
again.

`PlaybackManager.isCarConnected` is the new fact the scene delegate owns: it is
true between `templateApplicationScene(_:didConnect:)` and `…didDisconnect…`.

### 2. The route picker — there is no public API that picks a route

`AVRoutePickerView` is the only control the system gives;
`CPSessionConfiguration.supportsVideoPlayback` (iOS 26.4+) exists but the app
cannot obtain an instance of it (no accessor on `CPInterfaceController`, on the
scene or on UIKit). So the app cannot choose the car's display — it can only
offer the picture to it.

`CarOutputSwitch`'s "Play on Car Display" is therefore **two** things now:

* with a car connected — a plain `Button` that hands the picture over at once,
  and the system's list of displays is **never** shown;
* without a car — the old route picker, which is the only way to reach a
  display at all.

The switch between the two lives in one place: `PlaybackManager.needsRoutePicker`.

### 3. The Browser tab — a search template, and rows that work

> **Corrected 2026-11-03 (the seventh pass).** The Browser tab was made a
> **`CPSearchTemplate`** here, on the belief that *"a search template is a
> legal tab"*. **That belief was wrong and it killed the app** — the tab bar
> rejects a search template at **run time** and takes a **SIGABRT** at every
> CarPlay connect. The Browser tab is a **list** now and the address bar is
> **pushed** onto the stack; see
> [`2026-11-03-the-crash-and-the-automatic-handover.md`](2026-11-03-the-crash-and-the-automatic-handover.md).

CarPlay has no web view (Apple does not allow one), so the car's browser is an
address bar plus a list of places to go.

* the address bar is a **`CPSearchTemplate`** — the only CarPlay chrome with a
  text field — **pushed onto the stack**;
* the tab is a **list**: the way into the address bar, the page the phone shows
  now and the sites of the app's own catalogue (`BrowserCatalog`);
* picking a result opens it **on the phone** — `BrowserTabManager` applies the
  rule the phone always applied: a URL is a URL, anything else is a Google
  search. That rule now lives in one place, `BrowserTabItem.destination(for:)`;
* the phone's screen share is armed at the same time, which is the only way a
  page reaches a car.

`CarPlayBrowserSearch.openAddress` is a seam (like `CarPlayArtwork.fetchLogo`)
so the tests assert the address without loading anything.

The site's tiles are **cached** now: the browser draws a row of them on every
keystroke, at the car's scale.

## The criteria this pass added

| AC | Criterion | Test |
|----|-----------|------|
| 98 | With a car connected, "Play on Car Display" hands the picture over at once — the system's list of displays is never shown | `CarOutputSwitchTests` |
| 99 | The Browser tab's header is a search bar, and what is typed goes to the phone's own browser | `CarPlayTabTests` |
| 100 | A site of the browser opens on the phone | `CarPlayTabTests` |

AC61 was rewritten: the Browser tab is no longer a list of sections, so the
test drives `CarPlayBrowserSearch` instead.

## Files touched

| File | What changed |
|------|--------------|
| `CarTV/Sources/Services/PlaybackManager.swift` | `isCarConnected`, `needsRoutePicker`, `playOnCarDisplay()`, the hand-off's retry ladder |
| `CarTV/Sources/Views/Player/CarOutputSwitch.swift` | the pill is a button when a car is connected, the route picker otherwise |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | the Browser tab was a `CPSearchTemplate` (see the correction above — it is a list now); the scene owns `isCarConnected` |
| `CarTV/Sources/Views/CarMode/CarPlayTabs.swift` | `CarPlayBrowserSearch` (the browser), `CarPlayTabActions.openOnPhone` removed |
| `CarTV/Sources/Views/CarMode/CarPlayArtwork.swift` | the site's tiles are cached |
| `CarTV/Sources/Services/BrowserTabManager.swift` | `BrowserTabItem.destination(for:)` — the URL-or-search rule, in one place |
| `CarTV/Tests/CarPlayTemplateTests.swift` | AC61 rewritten, AC98–AC100 added |
| `CarTV/Tests/ReviewRegressionTests.swift` | the spy lost the protocol member that is gone |
| `docs/SPEC.md` | AC98–AC100; the non-goals now say what the app **cannot** do (pick the route, draw a page) |
| `AGENTS.md` | the seventh pass's gotchas |
| `CHANGELOG.md` | the three fixes |

## Verification

* `xcodebuild -sdk iphoneos -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build` → **BUILD SUCCEEDED**
* `scripts/device_test.sh` on the **physical iPhone 13** (`00008110-001C60423CB8401E`) — the whole suite, AC98–AC100 included
* the **iPhone 18 Pro simulator was not touched**: not booted, not installed
  to, not installed from. Every build used `generic/platform=iOS`.

## Still needs a human

* **The picture on a real car's screen.** The hand-off is the fix for a black
  display, and the device log is what proves it: the route has to be evaluated
  with the car's endpoint selected (`Local Playback = 0` and the endpoint
  "CarPlay (ScreenMain)"), and `isExternalPlaybackActive` has to become true.
* **The Browser tab on the car's screen.** Whether the system seeds a search
  template's results when it appears is the system's own behaviour — if it
  does not, the sites appear as soon as the field is touched.
* **A page on the car.** It can only arrive through the phone's screen share,
  and the broadcast is started by the user from the Control Center (iOS
  refuses a ReplayKit capture while CarPlay is connected, −5813).
