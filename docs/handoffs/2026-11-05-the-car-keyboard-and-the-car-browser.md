# Session: 2026-11-05 — the car's keyboard and the car's own browser

## Goal
- Goal: see [docs/SPEC.md](docs/SPEC.md)
- The live goal: a real working broadcast of the phone's screen to a car's
  display, plus all the playlists on the car.
- This segment's two requests:
  *"see the browser is dead for car display it work as remote controller for
  iphone i want that brower work on car display side not only iphone app
  side"*, and *"when i try to press any key of the on display keyboard so the
  behind pluto TV click so it not working"*, and *"see this keyboard not works
  use native one that use in officail Apple apps like apple map on the carplay
  also"*.

## Branch / state
`main`. The repository has **no remote**, so nothing was pushed. Everything
below is in the working tree and in the one commit at the end of the session.

## Done

### The car's own browser (AC159–AC162)
`CarPlay.framework` on iOS 27 has **no web template at all** — so the Browser
tab's `CPSearchTemplate` is a text field and a list of links, and it can only
ever be a **remote control for the phone**. The app's own car screen — the one
with a real `WKWebView`, the toolbar, the zoom control and the full-screen
video surface — lives in the **external-display** scene, and the system opens
that scene **only when the app asks** for it.

- `CarTV/Sources/App/CarDisplaySession.swift` (new) is the one place that
  knows whether the car has a screen of its own, asks for it
  (`UISceneSessionActivationRequest(role: .windowExternalDisplayNonInteractive)`
  + `UIApplication.activateSceneSession(for:errorHandler:)`), and carries an
  address to it. `CarPlaySceneDelegate` asks **when the CarPlay scene
  connects**; the external-display scene attaches and detaches itself.
- A page the car asks for goes to the car's own browser when there is one, and
  **falls back to the phone** when there is not (AC159, AC160). The ask happens
  **once** (AC161).
- **Measured on the device**: the phone **refuses** the second scene — *"The
  current device does not support multiple scenes."* — so on an iPhone the
  Browser tab stays a remote control and the page reaches the car through the
  phone's screen share. The ask is harmless where it is refused.

### The keyboard that ate the key presses (AC163, AC164)
`CPSearchTemplate` has **no keyboard of its own** (the header carries
`delegate` and nothing else) — the keyboard that comes up is the **car's**,
and it floats over the **bottom** of the list. The address bar's results were
the **whole catalogue of sites** (seventeen rows with big tiles), so a row was
**always** under the keyboard, and a key press landed on that row instead of
the key.

- Measured on the simulator's 1920×1080 car screen: the keyboard covers the
  bottom ~27 % (window y ≈ 445…585) and a result row's band is **full width**,
  so a key press at (391, 464) sits inside the Pluto TV row's band.
- The address bar's list is **short** now: the way back, what the user typed,
  and at most **two** matches (`CarPlayBrowserSearch.maximumRows`). The whole
  catalogue stays in the Browser tab's own list, one tap away (AC163).
- A site answers to its **name** as well as to its address — "HBO Max" is
  nowhere in "max.com", and the name is what the user reads on the row
  (AC164).
- Four older tests had to follow the change, because they looked a site up in
  the **empty** result list: AC61 now drives the Browser tab's own list (which
  is what the AC's name says), and AC100/AC141/AC162 type the site's name.

### The device script that believed a word
`scripts/device_test.sh` waited for a line matching `connected|available` —
and **"unavailable" contains "available"**. The script handed xcodebuild a
phone that was off the bus and the run died with *"Unable to find a
destination matching the provided destination specifier"*. The repo's own rule
(*"Test the link, not the word"*) is what the script does now: the udid comes
from the device list, and whether the phone can be driven is asked of
`xcodebuild -showdestinations`.

## In progress
- The **device suite** for this round **ran** (14:02–14:12): **175 passed,
  8 skipped, 6 failed**. The six are **the app process being killed
  mid-test**, not assertion failures — no crash report was written, and the
  previous instance was still holding the relay port when the next one
  started, so it had been **suspended in the background** (the phone locked
  itself, or it was picked up). None of the six touches the code this round
  changed, and the new `CarDisplaySessionTests` **passed** on the phone. The
  re-run needs a phone that is plugged in, unlocked and **left alone** for
  ten minutes.
- The **manual test on the car**: the user is testing by hand (see below).

## Blocked
- The phone is off the bus again (`devicectl`: *unavailable*, last seen
  14:14), so the suite cannot be re-run and the CarPlay Simulator has no
  device to attach to. The **cable** is the blocker, not the code.
- The re-run also has to **wait for the manual test** — a suite that starts
  while the user is driving the car's display takes the phone's screen over
  and ruins the test they are doing.

## Files touched
- `CarTV/Sources/App/CarDisplaySession.swift` (new)
- `CarTV/Tests/CarDisplaySessionTests.swift` (new)
- `CarTV/Sources/App/CarPlaySceneDelegate.swift`
- `CarTV/Sources/App/ExternalDisplaySceneDelegate.swift`
- `CarTV/Sources/Views/CarMode/CarPlayTabs.swift`
- `CarTV/Sources/Views/CarPlayVideoViewController.swift`
- `CarTV/Sources/Views/CarPlayVideoViewController+Actions.swift`
- `CarTV/Tests/CarPlayTemplateTests.swift`
- `scripts/device_test.sh`
- `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md`

## Decisions made
- The address bar's list is **short** rather than rich. The app cannot know
  where the car's keyboard is, so the only safe rule is *"no row under it"* —
  and a long list is the reason the key presses were stolen. The catalogue
  stays in the Browser tab's own list.
- The site's **name** is a match, not only its address. The name is what the
  user reads on the row.
- The app asks for the car's own screen **once**, when the CarPlay scene
  connects, and does not ask again while it is there.

## Decisions needed
- None outstanding. The two open questions from the earlier review (§1.24) —
  the relay's unauthenticated control channel and a `decidePolicyFor` backstop
  on the two web views — are still the user's to make, and are still written
  down rather than slipped in.

## Verification
- Compile check: `xcodebuild … -destination 'generic/platform=iOS'
  CARPLAY_CATEGORY=video build-for-testing` → **`TEST BUILD SUCCEEDED`** —
  re-run on the **committed** tree (`83b4c40`) at the end of the session.
- The **AC trace** is mechanical: **164 SPEC rows ↔ 164 distinct AC ids in
  `CarTV/Tests/`** — the same set, no more, no fewer (181 test functions in
  all).
- The **CarPlay Simulator**: the car's own screen, the floating keyboard and
  the catalogue were measured **on the car's display** — the geometry in
  "Done" is read off the simulator's window, not guessed.
- The **device suite**: this round's run **happened** — **175 passed, 8
  skipped, 6 failed** (14:02–14:12). The six are the app process killed,
  not assertion failures; the details and the evidence are in the review
  (§1.27 fault 11). The newest run that was **fully green** is the
  seventeenth pass's (**181 tests**, 7 skipped, **0 failures**).
- The **fixed gate is proven both ways**: the run under the *old* script
  handed xcodebuild the phone's id while the phone was off the bus and died
  with *"Unable to find a destination matching the provided destination
  specifier: { platform:macOS, … name:My Mac }"*; with the fix,
  `xcodebuild -showdestinations` **does not list the phone** at all, so the
  script keeps waiting instead of running a doomed build.
- The **commit security review** for `83b4c40`: *"no security issues found"*
  (`~/.claude/security/log.txt`). The **older** commit `936357f`'s review
  timed out ("the model's reply could not be read") — that review is still
  missing, and the tree has moved on since.

## Next steps for next session
1. Plug the cable in (or make sure the phone is on the same network) and let
   `scripts/device_test.sh` run — it is waiting for the phone now. The phone
   must be **unlocked and left alone** for the ten minutes the run takes:
   six tests died with the app in the last run because the phone was
   backgrounded (see §1.27 fault 11 of the review).
2. On the car: Browser tab → *"Search or type a URL"* → **type**. The
   characters must land in the search field and the row behind must **not** be
   selected. Then type a site's **name** ("HBO Max", "Prime Video",
   "Sony LIV") — the site must come up as a result.
3. Re-run `./kit/bin/vibe-verify` to confirm AC↔code↔tests still hold.

## Gotchas learned
- **CarPlay has no web template** — there is none in `CarPlay.framework` at
  all, so a template browser can only ever be a remote control for the phone.
- **A phone refuses the second scene** — *"The current device does not support
  multiple scenes."* The app's own log carries it, so the question is answered
  by the device's unified log, not by guessing.
- **`CPSearchTemplate` has no keyboard** — the keyboard is the car's, it
  floats over the bottom of the list, and a row under it takes the key
  presses.
- **The simulator's floating keyboard is the car's, not the app's** — it is
  drawn by the simulator's own `atve-kit`. There is no "native keyboard" an
  app can ask for instead; the app's only lever is what it puts *under* the
  keyboard.
- **"unavailable" contains "available"** — a waiter that greps the device list
  for a word hands xcodebuild a phone that is not there. Test the link.
