# Handoff — 2026-10-31 — "app is dead on the simulator" + parser bug sweep

## What was asked

1. Analyse the whole codebase, find bugs, review it, act on the findings, deliver a review.
2. (Mid-turn) "our app is dead not working on simulator side proper and only works on mobile app side".

## Outcome

The app was **never hung** on the simulator. Evidence collected:

| Claim | Evidence | Verdict |
|---|---|---|
| App is frozen | Process alive at ~21% CPU; `sample` showed 2720/2903 main-thread samples in `mach_msg` (94% idle) | Not frozen |
| App does not render | `simctl io booted screenshot` shows the full DrivePlay home screen | Renders fine |
| CarPlay does not connect | Console shows only `UIWindowSceneSessionRoleApplication`; no CarPlay scene requested | CarPlay scene never requested |
| Cockpit stuck on "ACQUIRING SATELLITES" | No location ever delivered to `SatelliteHUDService` | **Real bug — environmental trigger** |
| Cast tab spins forever | `RPScreenRecorder.isAvailable` is `false` on the Simulator; the code latched `isMirroringActive = true` *before* checking it | **Real bug — code** |

## Root causes and fixes

### Code fixes (shipped)

| File | Bug | Fix |
|---|---|---|
| `CarTV/Sources/Parsers/M3UParser.swift` | Title separator found via `lastIndex(of: ",")` → titles containing a comma truncated | Quote-aware `findTitleSeparator(in:)` |
| `CarTV/Sources/Parsers/M3UParser.swift` | `currentGroupTitle` never reset → an entry without `group-title` inherited the previous entry's group | `currentGroupIsExplicit` + `pendingGroupTitle`; `#EXTGRP` scoped to its own entry |
| `CarTV/Sources/Parsers/XtreamParser.swift` | Credentials interpolated raw → a password with `&`/`#`/`?`/`/` truncated the request (401, or 404 on every channel) | `encodeCredential(_:)` (RFC 3986 unreserved set) |
| `CarTV/Sources/Parsers/XtreamParser.swift` | Unbuildable stream URL fell back to the API endpoint, handing the player JSON | `compactMap` + `guard let streamURL` |
| `CarTV/Sources/Parsers/XtreamParser.swift` | Multi-category streams (`"1,2"`) grouped nowhere | Split on `,`, take the first match |
| `CarTV/Sources/Parsers/DLNADIDLParser.swift` | Parser state accumulated across `<item>` elements → 2 items merged into one garbled channel | Per-item reset; returns first item; MIME read from `protocolInfo` field 3 |
| `CarTV/Sources/Services/SourceHealthService.swift` | `.poor` was unreachable (the `else` branch returned `.fair`) | `else` → `.poor` |
| `CarTV/Sources/Views/CarPlayVideoViewController.swift` | Chevrons positioned against `view.bounds` instead of `homeContainer.bounds` → up-chevron 48pt low, down-chevron 26pt off-screen | Position against the container |
| `CarTV/Sources/Views/CarPlayVideoViewController.swift` | `isMirroringActive = true` set before `guard recorder.isAvailable` → Cast tab wedged forever on the Simulator | Check availability first; report "not supported in the iOS Simulator" |
| `CarTV/Sources/Views/Player/VideoPlayerView.swift` | ±10s buttons created at alpha 1 → the first tap hid them | Start at alpha 0 |
| `CarTV/Sources/Views/Player/DockedPlayerContainerView.swift` | `@State` channel snapshot never reconciled → the heart never updated | Snapshot kept in step on toggle |
| `CarTV/Sources/Views/Home/GroupDetailView.swift` | Same stale snapshot → the swipe label kept saying "Favorite" | Snapshot kept in step on toggle |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | The scene installed a custom `UIViewController` on the CarPlay window (`rootViewController`, `layer.zPosition = 99999`, a 0.1 s keep-on-top timer) behind an empty placeholder template. CarPlay renders **templates only** — no public `CarPlay.framework` header references `UIViewController` — so the custom UI could never appear | Rewritten template-only: `CPListTemplate` root (Favourites + Categories) → a **list** of the category's channels → `PlaybackManager` + `CPNowPlayingTemplate.shared`; `CPSearchTemplate` reachable from a nav-bar button; hijack, `zPosition` hack and timer deleted |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | The channel picker was a `CPGridTemplate`. Only `CPListItem` carries a `playbackConfiguration` (iOS 26.4+), so a grid could never tell CarPlay that a selection is video | The picker is a `CPListTemplate`; every channel row sets `playbackConfiguration(preferredPresentation: .video, playbackAction: .play)`, which is the sanctioned way to ask the system for the video surface |
| `CarTV/Sources/Services/PlaylistStore.swift` | `groups` applies the handset search box, so typing on the phone shrank the CarPlay catalogue | Added `allGroups` (the unfiltered index); CarPlay reads it |
| `CarTV/Sources/Services/PlexClient.swift` | `PlexPin` required a JSON key `expiresAt` that Plex never sends (it sends `expiresIn` + `createdAt`) → every pin response failed with `keyNotFound`, so Plex sign-in could never complete | Decoded `expiresIn` / `createdAt`; `expiresAt` removed (nothing referenced it) |
| `CarTV/Sources/Services/VoiceSearchManager.swift`, `CarTV/Sources/Views/Home/VoiceSearchOverlayView.swift`, `CarTV/Sources/Views/Home/HomeView.swift` | Voice search was dead code: no presenter, no caller, and neither the speech nor the microphone permission was ever requested — the sheet showed "Listening…" while nothing recorded. A tap left installed on the input node also trapped the next recording | Mic button on Home opens the overlay; speech **and** mic permissions requested; transcript matches a channel or category name and starts playback; the tap is always detached |
| `CarTV/Sources/Services/LocalMediaService.swift` | Two imports with the same filename (`clip.mp4` from two folders) were stored as the same file — the second overwrote the first. `index.json` was written non-atomically, so a crash mid-write left a truncated index and the whole vault failed to load | Stored names are prefixed with a fresh id; the index is written with `options: .atomic` |
| `CarTV/Sources/Views/CarPlayVideoViewController.swift` | The channel-logo `NSCache` had no cost limit — it grew with every logo ever seen and evicted nothing | 32 MB cost limit; each image stored with its approximate byte cost |
| `CarTV/Sources/Views/CarPlayVideoViewController.swift` | The car shelves were rebuilt three times at launch: the store republishes its channel list on every save, and the publisher also fires once on subscription, so every card and category was torn down and rebuilt for identical data | `ShelfSignature` (channel ids + favourite ids) gates the rebuild; the shelves are rebuilt only when the content actually differs |
| `scripts/auto_install.sh` | The device UDID and one machine's absolute DerivedData path were hardcoded, and the script looped forever when the phone was absent | Device detected at run time (first connected **physical** device, simulators skipped) or taken from `$1`/`DEVICE_UDID`; the `.app` is located in DerivedData or `APP_PATH`; the wait is bounded (`WAIT_SECONDS`, default 300) and ends in a clear error |
| `main` (repository root) | A stale 56 KB Mach-O binary compiled from the deleted `CarTV/Tests/main.swift`, unreferenced by `project.yml` or any script | Deleted |

### Environment (no code change)

```bash
xcrun simctl privacy booted grant location com.rushabh.cartvv
xcrun simctl location booted set 37.3317,-122.0301
```

Without a location the Cockpit card shows "ACQUIRING SATELLITES..." forever, because
`SatelliteHUDService.isSatelliteConnected` only flips in `didUpdateLocations`.

## Environment limitation — CarPlay cannot be attached to the simulator from the CLI

> **Correction (this section was wrong in the first version of this handoff.)** The claim
> "no CarPlay runtime is installed" was a bad inference from paths that Xcode 27 removed.
> The CarPlay Simulator **is** installed, at `/Users/radhikamac/Desktop/CarPlay Simulator.app`
> (v4.0, iOS 27.0), and it runs. The correct signal is that standalone app (or the
> `CarPlaySimulator.devicekitplugin` under `DeviceKit.framework`), not
> `simctl list devicetypes | grep -i carplay` — that list is always empty — and not the
> missing `Xcode.app/Contents/Developer/Applications/` folder.

```
/Users/radhikamac/Desktop/CarPlay Simulator.app             # present, running
xcodebuild -showdestinations                                # no CarPlay destination
xcrun simctl list devicetypes | grep -i carplay              # empty (meaningless signal)
```

CarPlay moved into Xcode 27's **Device Hub** (`CPSDeviceKitProvider`,
`CPSDeviceKitMenuItem`, `attachSession:callbacks:target:queue:`). There is no CLI route:
`devicectl` has no carplay/session/external-display subcommand, `simctl` has none, and the
CarPlay Simulator app declares no `CFBundleURLTypes` (no URL scheme). Xcode 27 ships no
`Simulator.app`, so the old `I/O ▸ External Displays ▸ CarPlay` menu is gone.

Attaching a device to the CarPlay display is therefore a **one-click Device Hub action**
(Xcode → Window ▸ Devices → iPhone 18 Pro → CarPlay). Until that happens, CarPlay code can
be written but not visually verified.

### Entitlement measurement (also corrected)

The first version of this handoff said the simulator build "embeds zero entitlements".
That was a measurement error: re-signing the built `.app` with `codesign --force` replaced
its signature, and the follow-up read then showed `{}`. Simulator entitlements live in the
Mach-O `__TEXT,__entitlements` section, which correctly contains
`application-identifier = 47T499AR2T.com.rushabh.cartvv` and
`com.apple.developer.carplay-audio = true`. **Entitlements were never a blocker.**

## Self-inflicted regression (introduced, detected, reverted)

`xcodegen generate` rewrites `CarTV/Resources/Info.plist` from `project.yml`, and `project.yml`
had `UISceneConfigurationName: "CarPlay"`. `AppDelegate` looks up
`UISceneConfiguration(name: "CarPlay Configuration", sessionRole: .carTemplateApplication)` — a
name that does not match leaves `sceneClass == nil`, so the scene is not a
`CPTemplateApplicationScene` and CarPlay breaks. Restored to `"CarPlay Configuration"` in
`project.yml` and regenerated.

**Gotcha:** `project.yml` is the source of truth for `Info.plist`. Never hand-edit the plist —
the next `xcodegen generate` overwrites it.

## Verification

```
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES test
→ Executed 46 tests, with 0 failures  ** TEST SUCCEEDED **
```

(The Simulator build has to be **signed**: an unsigned app has no
`application-identifier`, so the Keychain refuses every write with `-34018`.
Ad-hoc signing is enough. See the 2026-11-02 handoff.)

Re-run after the CarPlay rewrite: 5 (CarPlay templates) + 1 (catalogue isolation) + 14 (M3U)
+ 8 (Xtream/DLNA) = 28 tests; then + 2 (Plex pin) + 2 (offline vault) + 1 (install script)
+ 2 (car shelves) = **35 tests, 0 failures, TEST SUCCEEDED**. The rebuilt app installs and
launches on the booted simulator (pid alive after 6 s) and renders the home screen with
`GPS SAT-LOCK: ACTIVE`.

New `CarTVTests` target (`CarTV/Tests`, wired into the `CarTV` scheme) — 35 tests, names echo
the blueprint ACs. The old `CarTV/Tests/main.swift` assert harness was deleted: it was in no
Xcode target, and its fixture gave every entry a `group-title`, which is exactly why the
group-leak bug was never caught.

The iOS test bundle cannot spawn processes (`Foundation.Process` does not exist on iOS), so
`scripts/auto_install.sh` is covered by a static contract test (no device UDID, no absolute
machine path, bounded wait) and exercised from the shell:
`DEVICE_UDID=00000000-… APP_PATH=… WAIT_SECONDS=1 scripts/auto_install.sh` → exits 1 after
3 s with "no device available after 1s." (it used to loop forever).

`CarPlaySceneDelegate.makeSections(groups:favorites:owner:)` is `static` and takes its
inputs as arguments so the template structure can be tested without a connected scene —
`CPInterfaceController` cannot be created outside one. `owner` carries the handler wiring
and is `nil` in tests.

## CarPlay verification status — what is proven and what is not

| Claim | Status |
|---|---|
| The app builds and the 22 unit tests pass | **Proven** (xcodebuild output above) |
| The CarPlay delegate compiles against the real `CarPlay.framework` API | **Proven** — the exact call surface was type-checked against the iOS 27 SDK before writing the file (`CPListTemplate(title:sections:)`, `CPListSection(items:header:sectionIndexTitle:)`, `CPListItem.handler`, `CPGridButton(titleVariants:image:handler:)`, `CPNowPlayingTemplate.shared`, `CPSearchTemplate`, `leadingNavigationBarButtons`) |
| The templates render on a car screen | **Not proven** — needs the Device Hub attach (one click) or a real head unit |
| The video capability is granted | **Not proven** — Apple grants `com.apple.developer.carplay` per-app |

## Open items (NOT fixed — need a decision or a device)

1. **Entitlement mismatch.** `CarTV.entitlements` grants only `com.apple.developer.carplay-audio`
   (audio-only) while the app ships video content. Needs the `com.apple.developer.carplay`
   capability, which Apple grants per-app. **Ask first** — it is a capability change requiring
   a provisioning-profile update, and the device build stops signing until Apple grants it.
2. ~~Plaintext credentials persisted in `saved_channels.json` / `UserDefaults` /
   `WatchHistoryStore`~~ — **fixed 2026-11-02**, see
   [2026-11-02-credential-storage-ats-and-storekit.md](2026-11-02-credential-storage-ats-and-storekit.md).
3. ~~`http://` defaults in the Xtream/Jellyfin clients plus `NSAllowsArbitraryLoads: true`~~ —
   **fixed 2026-11-02** (one `URLPolicy`, `NSAllowsLocalNetworking` only).
4. ~~ReplayKit renderer touched from a non-main queue; screen capture never stopped on CarPlay
   scene disconnect~~ — **fixed 2026-11-02**.
5. ~~`StoreKitManager` has no StoreKit 2 integration~~ — **fixed 2026-11-02** (real StoreKit 2
   layer; the product id and the paywall placement are still a product decision).

Fixed since the first version of this list: `PlexPin.expiresAt`, the unbounded logo `NSCache`,
the `LocalMediaService` filename collisions and non-atomic index, the dead voice search,
`scripts/auto_install.sh`, the stale root `main` binary, and the triple shelf rebuild at launch.

## Files changed

```
CHANGELOG.md                                              (new)
AGENTS.md                                                 (new; later updated with the CarPlay
                                                          template rule + measurement traps)
docs/handoffs/2026-10-31-simulator-deadness-and-parser-fixes.md  (new)
CarTV/Tests/M3UParserTests.swift                         (new, 14 tests)
CarTV/Tests/SourceParserTests.swift                      (new, 10 tests)
CarTV/Tests/CarPlayTemplateTests.swift                   (new, 6 tests)
CarTV/Tests/LocalMediaServiceTests.swift                 (new, 2 tests)
CarTV/Tests/InstallScriptTests.swift                     (new, 1 test)
CarTV/Tests/InCarShelfTests.swift                        (new, 2 tests)
CarTV/Tests/main.swift                                   (deleted)
main (repository root)                                    (deleted; stale probe binary)
CarTV/Sources/Parsers/M3UParser.swift
CarTV/Sources/Parsers/XtreamParser.swift
CarTV/Sources/Parsers/DLNADIDLParser.swift
CarTV/Sources/Services/SourceHealthService.swift
CarTV/Sources/Services/PlaylistStore.swift               (+ allGroups)
CarTV/Sources/Services/PlexClient.swift                 (+ PlexPin key fix)
CarTV/Sources/Services/VoiceSearchManager.swift          (permissions + tap teardown)
CarTV/Sources/Services/LocalMediaService.swift           (id-prefixed names, atomic index)
CarTV/Sources/App/CarPlaySceneDelegate.swift             (rewritten template-only)
CarTV/Sources/Views/CarPlayVideoViewController.swift
CarTV/Sources/Views/Home/VoiceSearchOverlayView.swift    (rewritten)
CarTV/Sources/Views/Home/HomeView.swift                  (+ voice search)
CarTV/Sources/Views/Player/VideoPlayerView.swift
CarTV/Sources/Views/Player/DockedPlayerContainerView.swift
CarTV/Sources/Views/Home/GroupDetailView.swift
scripts/auto_install.sh                                  (rewritten: no hardcoded device/path, bounded wait)
project.yml                                               (+ CarTVTests target)
CarTV.xcodeproj/project.pbxproj                          (regenerated by xcodegen)
CarTV/Resources/Info.plist                               (regenerated by xcodegen)
```
