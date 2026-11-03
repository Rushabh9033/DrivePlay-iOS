# Handoff — 2026-11-03, the last pass (repo, review, dead code)

## Where the work stands

The Milestone 1 work (four CarPlay tabs, the phone↔car picture switch, the
voice-search fix) was finished earlier today and is written up in
[`docs/review-2026-11-03.md`](../review-2026-11-03.md) and
[`2026-11-03-voice-search-and-device-test-fixes.md`](2026-11-03-voice-search-and-device-test-fixes.md).

This pass closed the remaining open items that did not need the phone:

| Item | State |
|------|-------|
| **The project is now a git repository** | `git init -b main`, first commit `e2415cd` (the whole app), then `f778220` (the SPEC trace) and `6fe30c2` (the dead browser). `.gitignore` now also keeps out the agent workflow state and the `REA_workflow` archive. |
| **The SPEC's test trace points at classes that exist** | AC7/AC8 live in `SourceParserTests`, AC9/AC10 in `LocalMediaServiceTests` — the table still named `PlexTests` and `OfflineVaultTests`, which were never written. All **68** ACs have a test; there are **90** test functions in all; no test names an AC the spec does not have. |
| **A second, unused browser is gone** | `CarBrowserView` was never presented by anything — its own `WKWebView`, its own tab state, its own preset-site list, while the car's Browser tab uses `BrowserCatalog`. Two sources of truth for the same list. The `WKWebView` wrapper it held moved next to the browser that uses it (`InAppBrowserView.swift`); the rest of the file is deleted. |
| **The project builds for the device** | `xcodebuild … -sdk iphoneos -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build-for-testing` → `** TEST BUILD SUCCEEDED **`. The built app carries `carplay-audio` **and** `carplay-video`. 93 warnings, all pre-existing (Swift 6 migration notes, deprecated `onChange(of:perform:)`, an `AVAssetWriter` `Sendable` note) — none in the files this milestone touched. |
| **`xcodegen generate` produces no drift** | The committed `Info.plist` and `project.pbxproj` are exactly what the generator writes. |

## Still blocked on hardware — the phone

The physical iPhone 13 (`00008110-001C60423CB8401E`) left the USB bus at about
13:47 and has not come back (`devicectl` reports it `unavailable`). Two things
need it:

1. **The device test suite.** The fixes for AC34 (the capture seam) and AC47
   (the loopback blocker) are written and compile, but have not been *run* on
   the phone. The last device run (13:40) had AC67/AC68 green and AC34/AC47
   red; both red ones were fixed afterwards.
2. **The photographs of the car's screen.** The four tabs have to be shown on
   the car's display to be answered honestly. Xcode 27's CarPlay Simulator
   hosts **physical devices only** — there is no simulator that can show them.

`/tmp/after_phone2.sh` (running in the background) waits for the phone, runs
the suite into `/tmp/dev_full3.log`, launches the app and drives the CarPlay
Simulator's window to capture `/tmp/cp-driveplay3.png`. It needs the phone
plugged in **and unlocked**.

## The new lesson (added to `AGENTS.md`)

> **A deleted source file needs `xcodegen generate` too.** The generated
> `project.pbxproj` names every source file, so removing one from the disk
> leaves the build failing with *"Build input file cannot be found"* — the
> file is still in the project.

## If the phone does not come back

The build, the tests (they compile) and the docs are all in place; what is
missing is the *run* on the device and the picture of the car's screen. The
suite is one command away:

```bash
scripts/device_test.sh          # waits for the phone, then runs the suite
```
