# Handoff — the car crash is fixed (2026-11-03)

Follows `2026-11-02-carplay-presenttemplate-crash.md`. The crash that killed the
app on every row tap is fixed; **the fix is not yet verified on a car**, because
the iPhone 13 was offline for this whole session (last seen 2 Nov 18:18).

## 1. The root cause was not what the crash log suggested

Yesterday's note blamed the *timing*: "presenting a template from inside a
`CPListItem` handler". **That was wrong.** The timing is fine — Apple's own
samples push a template from a selection handler. The real cause is in the
iOS 27 SDK's `CPInterfaceController.h`:

```
/**
 Present a template modally over the navigation hierarchy. ...
 @note Supported template types: @c CPActionSheetTemplate, @c CPAlertTemplate, @c CPVoiceControlTemplate
 ...
 @note If the template presentation is not successful AND no completion block is specified, an exception will be thrown.
 */
- (void)presentTemplate:(__kindof CPTemplate *)templateToPresent
               animated:(BOOL)animated
             completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;
```

Two facts, and together they are the crash:

1. **`presentTemplate` accepts only action sheets, alerts and voice control.**
   `CPNowPlayingTemplate` is not one of them, so the presentation *failed*.
2. **A failed presentation with no completion handler throws an `NSException`** —
   an uncaught ObjC exception, so the process aborts (SIGABRT).

The app called `presentTemplate(CPNowPlayingTemplate.shared, animated: true,
completion: nil)` — an unsupported template **and** no completion handler. Hence
`+[NSException raise:format:]` → `presentTemplate:animated:completion:` in the
crash log, and the app dying on every tap. The exception *reason string* is not
in the `.ips`, which is why the log alone could not tell us this.

**The rule to keep: never call a CarPlay template API without a completion
handler.** A failed call then reports an error instead of killing the app.

## 2. What changed

| File | Change |
|------|--------|
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | **The app no longer presents the now-playing template.** `presentNowPlaying()` became `prepareNowPlaying()`: it only configures `CPNowPlayingTemplate.shared`. The now-playing screen is the **system's** to present — the rows carry a `CPPlaybackConfiguration` and CarPlay shows the media presentation itself when the item is selected ("the style of media presentation shown after selecting the item"), presenting the shared template on the app's behalf. It is also where the system draws the **video surface**, so an app-presented template would stand between the system and the picture. |
| same file | `pushChannels` and `presentSearch` now carry a completion handler that logs the failure. `setRootTemplate` already had one. |
| `CarTV/Tests/CarPlayTemplateTests.swift` | **AC45** (`CarPlayPresentationTests`): the delegate never presents the now-playing template, no template call is made without a completion handler, and the shared template is the instance the system presents. |
| `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md` | The AC, the fix, and the corrected gotcha (yesterday's entry named the wrong cause). |

`scripts/run_tests.sh` → **67 tests, 0 failures**.

## 3. How the test can fail again

The test reads `CarTV/Sources/App/CarPlaySceneDelegate.swift` from the repository
(the iOS test bundle cannot spawn processes, so — like the install script — the
contract is checked statically). It fails if anyone:

* writes `presentTemplate(nowPlaying…)` or `presentTemplate(CPNowPlayingTemplate…)`, or
* writes `completion: nil` for any template call.

That is the whole crash class, not just this instance of it.

## 4. Still open

* **The fix is unverified on a car.** The iPhone 13 was offline for this whole
  session, and the CarPlay Simulator in Xcode 27 attaches to **physical devices
  only** (see `AGENTS.md`) — so there is no way to reproduce the crash or the
  fix without the phone. Plug the phone in, install, attach the CarPlay
  Simulator, tap a row: **the app must stay alive**.
* **What the car shows after the fix** — with the system presenting the
  now-playing template, the car's now-playing area shows the channel (the app
  publishes `MPNowPlayingInfoCenter` metadata: title, group, artwork). Whether
  the system also takes over the whole screen is a thing to look at on the car.
* **The search button** still presents `CPSearchTemplate` modally, now with a
  completion handler. `CPSearchTemplate` is *not* in `presentTemplate`'s
  supported list either, so if it is refused the log says
  `DRIVEPLAY present search failed: …` and the fix is to push it instead
  (`pushTemplate`) — the same shape as the now-playing fix.
* **Apple's CarPlay Video grant** — unchanged, still the blocker for the picture
  on a real car (`docs/carplay-video-request.md`).
* **Whether iOS 27 still launches the broadcast upload extension** — one tap by
  the user on the phone.

## 5. Verification

```bash
./scripts/run_tests.sh     # 67 tests, 0 failures
```

Read the log for `Terminating app` as well as the exit code: xcodebuild re-runs
a suite after a host crash, so a green exit code can be the retry.
