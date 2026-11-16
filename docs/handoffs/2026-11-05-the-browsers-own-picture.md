# Session: 2026-11-05 — the browser's own picture (the browser that runs on the car's display)

## Goal
- Goal: see [docs/SPEC.md](docs/SPEC.md)
- The live goal: a real working broadcast of the phone's screen to a car's
  display, plus all the playlists on the car.
- This segment's request, verbatim: *"i want 100% working broweser on car
  display screeen not as remort in for Iphones"*.
- The binding environment rule, verbatim: *"bro dopn't touch iphone 18pro
  simulator use only my pyshicall device to do ay thing"* — every build and
  test used `generic/platform=iOS` or the physical phone
  `00008110-001C60423CB8401E` (iPhone 13). The iPhone 18 Pro simulator was
  never booted. `scripts/carplay_simulator.sh` was never run.

## Branch / state
`main`, dirty. The repository has no remote, so nothing was pushed.

## Done

### The browser now runs **for the car**, not for the phone (AC165–AC169)

The eighteenth pass established the half that cannot be argued with:
**`CarPlay.framework` has no web template**, so a template can never hold a
page — the Browser tab's `CPSearchTemplate` is a text field and a list of
links. But the page still went to the **phone**, which made the car's browser
a remote control for the iPhone.

The car *does* draw one thing the app controls: **the video the app plays**.
So the page does not need a template — it needs to be **the picture**:

    the app's own WKWebView → a picture → the encoder → a local HTTP server
    → the app's AVPlayer → the car's AirPlay endpoint ("CarPlay (ScreenMain)")

That is the chain the TV channels already use, and the car draws it.

- `CarTV/Sources/Services/CarBrowserStream.swift` (new) — a web view with **no
  window**, captured ten times a second with `takeSnapshot`, drawn onto the
  encoder's canvas (`ScreenFrameScaler`), encoded (`LiveScreenWriter`), served
  over the local HTTP server with its 128-bit token, and played by the app.
- The **car's own rows** drive that web view: Back, Forward, Reload, Scroll
  up, Scroll down, Close (`CarBrowserCommand`, `CarPlayTabs.browserSections`).
- The old paths survive: the app's own car screen (external-display scene)
  first, the phone's browser and its screen share as the last resort, and a
  browser that could not start falls back to the phone rather than showing a
  black screen.
- The phone's screen share is stopped **before** the browser takes the
  player — `ScreenShareService.tearDown()` calls `stopScreenShare()`, which
  would have killed the browser's picture.

### What had to be measured on the phone first

| Question | Answer |
|---|---|
| Does a web view in **no window at all** still render? | **Yes** — 5 of 5 good pictures, **11–21 ms** each |
| Its layout viewport | **exactly 1280×720** — the car's 16:9 |
| A web view **in a window** | 1280×**639** — the safe area eats 81 pt |
| The picture's size | **3840×2160 px** — `image.size` is 1280×720 **points** (3×) |

The window-less web view is the one the car wants: the page is laid out for
the car's screen, not the phone's.

### The bug the measurement itself found
The first sampler mixed `image.size` (points) with `cgImage` (pixels), so the
"centre" of the picture was read at pixel 640 instead of 1920 — and a
perfectly good page was measured as *"the black square is not where it should
be"*. The page was right; the measurement was wrong. A second trap: the
page's layout is top-down and Core Image's canvas is bottom-up, so a marker
at the **top** of the page can be at the **bottom** of the picture.

## In progress
- The **last mile**: the picture on the car's own display, through the CarPlay
  Simulator, with the phone attached. The chain is proven to the last public
  API the app owns; what the system does with it is the simulator's part, and
  the simulator needs the phone on the cable.

## Blocked
- Nothing in the code. The CarPlay Simulator in Xcode 27 attaches to
  **physical devices over USB only**, so the manual check needs the cable.

## Files touched
- `CarTV/Sources/Services/CarBrowserStream.swift` (new)
- `CarTV/Tests/CarBrowserStreamTests.swift` (new)
- `CarTV/Sources/Views/CarMode/CarPlayTabs.swift`
- `CarTV/Sources/App/CarPlaySceneDelegate.swift`
- `CarTV/Tests/CarPlayTemplateTests.swift`
- `CarTV/Tests/ReviewRegressionTests.swift`
- `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md`

## Decisions made
- **The web view has no window.** Measured: it still renders, and it is the
  only hosting whose layout viewport is exactly the car's 1280×720. A
  window-hosted web view lays out at 1280×639 and cuts the page off.
- **The car draws the page as video, not as a template.** There is no web
  template; the video surface is the only picture the app controls.
- **The phone's screen share is stopped before the browser takes the player.**
  Otherwise the share's end would kill the browser's picture.
- **The SPEC's non-goal was rewritten.** It said *"Drawing a web page on the
  car's screen"* was out of scope, with the reason *"the page it opens runs in
  the app's own browser on the phone"*. The user's request overturns that, so
  the non-goal now says what is true: a page can never be a **template's**
  content, and it reaches the car as the picture the app plays.

## Decisions needed
- None outstanding. The two open questions from §1.24 of the review — the
  relay's unauthenticated control channel and a `decidePolicyFor` backstop on
  the two web views — are still the user's to make and are still written down
  rather than slipped in. The car's browser is a **third** web view, so the
  backstop question now covers it too.

## Verification
- Compile check: `xcodebuild … -destination 'generic/platform=iOS'
  CARPLAY_CATEGORY=video build-for-testing` → **`TEST BUILD SUCCEEDED`**.
- The **AC trace** is mechanical: **169 SPEC rows ↔ 169 distinct AC ids in
  `CarTV/Tests/`** — the same set, no more, no fewer, and no name twice.
- The **device suite** on the physical iPhone 13: **`Executed 194 tests, with
  9 tests skipped and 0 failures`** → **`** TEST SUCCEEDED **`** (43.7 s),
  **no app restart**. The nine skips are the repository contract tests (a
  device has no checkout to read).
- The five new tests, on the phone: AC165 (0.390 s), AC166 (0.506 s), AC167
  (6.513 s), AC168 (0.011 s), AC169 (0.048 s).

## Next steps for next session
1. Plug the cable in, attach the phone to the **CarPlay Simulator**, and open
   the Browser tab on the car: pick a site and the page must appear **on the
   car's display**, not on the phone. The phone's own picture stays dark while
   the car has it, and the car's Back / Scroll rows must move the page.
   A click on the car's display is only made after
   `NSWorkspace.frontmostApplication` says *CarPlay Simulator* is frontmost.
2. Re-run `./kit/bin/vibe-verify` to confirm AC↔code↔tests still hold.

## Gotchas learned
- **A web view with no window at all still renders** — five of five good
  pictures, 11–21 ms each, and a layout viewport of exactly 1280×720.
- **The picture is three times the view** — `takeSnapshot` gives 3840×2160 px
  while `image.size` says 1280×720 points. Mixing the two samples the wrong
  place entirely.
- **The encoder's canvas and the web view's layout disagree about which way
  is up** — Core Image is bottom-up, the page is top-down. A marker at the
  top of the page can be at the bottom of the picture.
- **The share's `tearDown()` calls `stopScreenShare()`** — so the phone's
  screen share has to be stopped *before* the car's browser takes the player.
