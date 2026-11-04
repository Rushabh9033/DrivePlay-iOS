# Session: 2026-11-04 — the browser mechanism

## Goal
- Goal: see [docs/SPEC.md](docs/SPEC.md)
- The live goal: a real working broadcast of the phone's screen to a car's
  display, plus all the playlists on the car.
- This segment's request: *"fix wholoe browser mechaniosm try to implement
  from scratch but implement becuase its dead on car play display side"* —
  and the report behind it: *"when i try to write anything inside keyboard of
  the brower so the browserscreen close and redirect to home"*.

## Branch / state
`main`. The repository has **no remote**, so nothing was pushed. Everything
below is in the working tree and in the one commit at the end of the session.

## Done
Seven faults, each with a test:

1. **The ad blocker tore the content process down under the page**
   (AC152). `AdBlockerEngine.apply(to:)` did `removeAllContentRuleLists()` +
   `add()` on the **live** web view's content controller on **every**
   navigation. A `WKWebViewConfiguration` is copied when the web view is
   made, but its `userContentController` is a **shared reference** — so the
   rule store of the content process was torn down while the page was still
   loading. The device's own log says what that does:
   `GPUProcessProxy::gpuProcessExited: reason=Crash` and four
   `WebProcessProxy::processDidTerminateOrFailedToLaunch: reason=Crash`, with
   **no crash report** from the app. The rules are applied **once** now, and
   `apply(to:)` returns whether it changed anything.
2. **The crash handler emptied the tab's address** (AC155) — and an empty
   address **is** the start page, so that *was* the "redirect to home". The
   address is **kept** now, the tab says *"The page crashed"*, and the page is
   reloaded **once** and not in a loop.
3. **The address bar showed the page's *previous* address.** The mirror read
   `tab.urlString` inside `objectWillChange` — which fires **before** the
   value changes. It now subscribes to the `$published` publisher, which
   carries the **new** value.
4. **The phone's two search boxes were one text field** (AC156, AC157). The
   address bar and the start page's own box shared one `@State`, so the text
   appeared in both and the bar was filled over what the user had typed. Two
   fields now, each with its own text; the bar is filled only **while it is
   empty**.
5. **The car's search could never work.** `presentSearch()` *presented* a
   `CPSearchTemplate`, and `presentTemplate` accepts only an action sheet, an
   alert and voice control — the presentation failed every time and the Search
   button did nothing at all. It is **pushed** onto the stack now.
6. **The address bar had no way back** (AC153, AC154). A `CPSearchTemplate`
   does not conform to `CPBarButtonProviding`, so it cannot carry a
   navigation bar button: the way back is a row of its own list (*"Back to
   sites"*, *"Back to channels"*). The channel search also rebuilt thirty
   rows — and thirty pictures at the car's scale — for **every keystroke**;
   the rows are built once and filtered afterwards, in a bounded cache.
7. **A page the car asked for never came to the phone** (AC158). The
   selected tab was a `@State` **inside** `MainTabView`, so nothing outside
   the view could change it: the car asked for a page, the page opened on the
   phone's browser tab, and the phone stayed on the tab it was on. The share
   the car needs captures **the phone's screen** — so the car was waiting for
   a share of the wrong screen, and the phone's *"the car is waiting"* banner
   (which carries the button that starts the share) was on the hidden tab
   too. The selection is shared now (`AppTabSelection`) and the browser comes
   to the front.

Two older tests broke while the way-back row was being made the first row:
AC69 and AC99 both took `results.first` to be the row they meant. They look
their row up **by its text** now.

## In progress
- Nothing. The code is in, the tests are in, the docs are in.

## Blocked
- **The CarPlay Simulator run.** The phone's **USB link dropped** during the
  session — `devicectl device info details` reports
  `Transport Type: localNetwork` — and Xcode 27's CarPlay Simulator attaches
  to physical devices **over USB only**: its *Sessions* menu says *"No
  Devices Connected"*. A USB device did turn up during the session, but it
  was **another user's phone** (khushi's iPhone 11) — not ours to drive, and
  the simulator does not list it either. The templates are covered by the
  tests; the last mile needs **our** phone on the cable.

## Files touched
- `CarTV/Sources/Services/AdBlockerEngine.swift` — the rule list is applied
  **once**
- `CarTV/Sources/Services/BrowserTabManager.swift` — the crash handler keeps
  the address; the address mirror reads the **new** value
- `CarTV/Sources/Services/ScreenShareService.swift` — a page the car asks for
  brings the browser to the front
- `CarTV/Sources/App/AppTabSelection.swift` — **new**: the tab the app shows,
  shared (`MainTab` moved here)
- `CarTV/Sources/Views/MainTabView.swift` — the tab comes from the shared
  selection
- `CarTV/Sources/Views/Browser/InAppBrowserView.swift` — `BrowserAddressBoxes`
  (two fields, one each), the submit takes the text **first**
- `CarTV/Sources/App/CarPlaySceneDelegate.swift` — the channel search is
  **pushed**, the rows are cached and bounded, the way back is a row
- `CarTV/Sources/Views/CarMode/CarPlayTabs.swift` — the address bar's
  *"Back to sites"* row; `CarPlayTabActions.pushChannelSearch()`
- `CarTV/Tests/AdBlockerTests.swift` — AC152
- `CarTV/Tests/CarPlayTemplateTests.swift` — AC153, AC154, AC158; AC69 and
  AC99 look their row up by its text
- `CarTV/Tests/ReviewRegressionTests.swift` — AC155, AC156, AC157
- `AGENTS.md` (the sixteenth and seventeenth passes' gotchas), `CHANGELOG.md`,
  `docs/SPEC.md`, `docs/review-2026-11-03.md` (§1.25, §1.26)

## Decisions made
- **The rule list is applied once, and `apply(to:)` says so.** The caller
  needs to know whether the page has to be loaded again for a change to be
  seen — that is why the method returns a `Bool` rather than `Void`.
- **The crash handler keeps the URL.** Sending the tab back to the start page
  is the exact symptom the user reported, so the tab says what happened
  instead and the browser's own reload button brings the page back.
- **The way back out of a pushed search is a row, not a button.** There is no
  other way: `CPSearchTemplate` does not conform to `CPBarButtonProviding`.
- **The App Group was not added.** It is still the user's decision (it is
  another Apple-granted capability) — see §1.24 of the review.

## Verification
| What | How |
|------|-----|
| The compile | `xcodebuild … -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build-for-testing` → **TEST BUILD SUCCEEDED** |
| The **whole suite on the physical phone** | `scripts/device_test.sh` → **181 tests, 7 skipped, 0 failures** |
| The new tests | shown as *passed* in the run (not skipped): AC152–AC158, AC69, AC99 |
| The AC trace | **158 SPEC rows ↔ 158 test names**, the same set, mechanically checked |
| The **Simulator** | **not used** — the iPhone 18 Pro simulator was never booted |
| The CarPlay Simulator | **not possible** — the phone is on the local network; the *Sessions* menu says *"No Devices Connected"* |

## Next steps for next session
1. Plug the phone back in and drive the **Browser tab** in the CarPlay
   Simulator: the *"Search or type a URL"* row → the address bar → type →
   the page opens on the phone → the *"Back to sites"* row pops the bar.
   Watch for `DRIVEPLAY CarPlay scene connected` in the app's console
   (`devicectl device process launch --console` bridges it; `idevicesyslog`
   needs the cable).
2. Ask the user about the **App Group** for the relay — the one security
   decision that is theirs to make.
3. The two things that still need a real head unit: the **picture on the
   car** and the car's **browser** (a `CPSearchTemplate` pushed onto the
   stack).

## Gotchas learned
- **A `WKWebViewConfiguration` is copied, but its `userContentController` is
  a shared reference.** So a content rule list added later reaches the web
  view that is already open — and *taken away* reaches it too, under the page
  that is loading.
- **An empty address IS the start page.** "The crash handler emptied the
  URL" and "the app redirected to the home screen" are the same bug.
- **`objectWillChange` fires *before* the value changes.** A mirror that
  reads the old value inside it is always one change behind.
- **`presentTemplate` accepts an action sheet, an alert and voice control —
  nothing else.** A search template has to be **pushed**.
- **A `CPSearchTemplate` cannot carry a navigation bar button** — it does not
  conform to `CPBarButtonProviding` — so the way back is a row of its own
  list.
- **Two text fields, one `@State`, is one field.**
- **The CarPlay Simulator needs the phone over USB.** Over Wi-Fi the phone
  is still a perfectly good test target (`devicectl` works, the suite runs)
  — but the *car* is not there.

<!-- context metadata (do not edit) -->
- session_id: unknown
- started: 2026-11-04T16:00:00
- cwd: /Users/radhikamac/carTv-iptv
- branch: main
- written_by: Claude Code
