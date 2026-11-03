# Handoff — the crash at every car connect, and the automatic handover (2026-11-03)

## The two defects this pass answers

1. *"app crashing on carplay display side"* / *"instant crash after load this
   screen"* — **the app died at every CarPlay scene connect**. The device's
   crash reports say it plainly, six times over the same evening:

   ```
   objc_exception_throw → +[NSException raise:format:] → -[CPTabBarTemplate validateTemplates:]
   ```

2. *"when user start video on mobile from our app so automatic video start in
   car display"* — a video started on the phone has to go to the car's display
   **by itself**.

## 1. The crash — the tab bar rejects a search template

The Browser tab had been made a **`CPSearchTemplate`**, because it is the only
CarPlay chrome with a text field and the user asked for an address bar.

* The **compiler** accepts it: `CPTabBarTemplate(templates:)` takes any
  `CPTemplate`, so the app built, signed and installed.
* The **runtime** does not: `-[CPTabBarTemplate validateTemplates:]` **raises
  an `NSException`** when one of the tab templates is a search template. An
  uncaught ObjC exception aborts the process — **SIGABRT**, every connect.

The crash reports (`CarTV-2026-11-03-173042.ips` and five more: 17:32:33,
17:42:48, 17:42:52, 17:49:15, 17:50:45) carry the stack above, so the cause
was never in doubt.

### The fix

* the Browser tab is a **`CPListTemplate`** — the way into the address bar
  (*"Search or type a URL"*), the page the phone shows now (*"On the phone
  now"*) and the sites of the app's own catalogue, each with its tile;
* the address bar is a **`CPSearchTemplate`**, **pushed** onto the stack
  (`pushTemplate`) — the stack takes it, the tab bar does not;
* the tab bar is built through `CarPlaySceneDelegate.makeTabBar(_ templates:
  [CPListTemplate])`, so the **compiler** refuses a search template there. The
  rule is in the type, not in a comment that can rot.

Picking a site or a search result opens it on the phone (CarPlay has no web
view) and the address bar pops back to the list — so the site's rows work
again.

`CPSearchTemplate.delegate` is **`weak`**, so the scene holds the delegate
itself (`browserSearch`) and assigns it to the address bar every time the bar
is pushed.

## 2. The automatic handover — a video started on the phone goes to the car

`PlaybackManager.play(channel:presentation:)` now hands the video over as soon
as a car is connected:

```swift
if isCarConnected && presentation != .hidden {
    handOffToCar()
}
```

* `presentation == .hidden` is the car asking for the video itself — the
  picture is already the car's, and handing it over again would only take it
  away from the surface the user is watching;
* without a car the video stays on the phone (`.docked`);
* `handOffToCar()` reuses the ladder the sixth pass built — the picture is
  offered at once and again after 3 s, 8 s and 20 s — which is what makes the
  system re-evaluate the AirPlay route once the car's video endpoint exists.

## The criteria this pass added

| AC | Criterion | Test |
|----|-----------|------|
| 101 | The Browser tab is a **list** — the way into the address bar, the page the phone shows now, and the app's own sites | `CarPlayTemplateTests` |
| 102 | The tab bar is built from **lists** only — the tab bar rejects a search template and takes the app down with it | `CarPlayTemplateTests` |
| 103 | A video started on the phone goes to the car's display at once when a car is connected | `PlaybackManagerTests` |

AC102 is the regression test for the crash: it builds the tab bar the way the
scene builds it and asserts that **every** template in it is a list.

## Files touched

| File | What changed |
|------|--------------|
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | the Browser tab is a list; `makeTabBar([CPListTemplate])`; the address bar is pushed (`pushBrowserAddressBar`) and popped (`popBrowserAddressBar`) |
| `CarTV/Sources/Views/CarMode/CarPlayTabs.swift` | `CarPlayTemplates.browserSections(currentURL:owner:)`; `CarPlayTabActions` gained `pushBrowserAddressBar()` and `openOnPhone(address:)`; `CarPlayBrowserSearch.dismissAddressBar` |
| `CarTV/Sources/Services/PlaybackManager.swift` | the automatic hand-off in `play(channel:presentation:)` |
| `CarTV/Tests/CarPlayTemplateTests.swift` | AC101, AC102 |
| `CarTV/Tests/PlaybackManagerTests.swift` | AC103 |
| `CarTV/Tests/ReviewRegressionTests.swift` | the spy implements the two new protocol members |
| `CarTV/Tests/VoiceSearchTests.swift` | the two temporary diagnostic tests and the `import CarPlay` are gone |
| `docs/SPEC.md` | AC101–AC103; the sixth pass's paragraph about the search template corrected |
| `AGENTS.md` | the falsified gotcha (*"a `CPSearchTemplate` can be a tab"*) corrected with the crash evidence |
| `CHANGELOG.md` | the crash fix and the automatic hand-off |
| `docs/review-2026-11-03.md` | §1.16 (this pass), §2's Browser row, §3's numbers |

## Verification

* `xcodebuild -sdk iphoneos -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build` → **BUILD SUCCEEDED**
* `scripts/device_test.sh` on the **physical iPhone 13**
  (`00008110-001C60423CB8401E`) → **`Executed 125 tests, with 7 tests skipped
  and 0 failures (0 unexpected) in 34.148 seconds`** → `** TEST SUCCEEDED **`
* the seven skips are the repository contract tests, which read a file of the
  checkout that does not exist on the phone (`RepositoryFixture.skipUnlessPresent()`)
* the **iPhone 18 Pro simulator was not touched**: not booted, not installed
  to, not installed from. Every build used `generic/platform=iOS`.

## Still needs a human

* **One tap: open DrivePlay from the car's app list.** That is what proved the
  crash, so it is what proves the fix — the app must come up on the car and
  stay up. (The CarPlay Simulator's own UI did not answer the app-grid clicks
  in this session, so the end-to-end connect could not be driven from the Mac.)
* **The picture on a real car's screen.** The hand-off is the fix for a black
  display, and the device log is what proves it: the route has to be evaluated
  with the car's endpoint selected (`Local Playback = 0` and the endpoint
  "CarPlay (ScreenMain)"), and `isExternalPlaybackActive` has to become true.
* **A page on the car.** It can only arrive through the phone's screen share,
  and the broadcast is started by the user from the Control Center (iOS
  refuses a ReplayKit capture while CarPlay is connected, −5813).
