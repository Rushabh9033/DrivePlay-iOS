# Handoff — 2026-11-02 — CarPlay video entitlement, automatic testing, the Pro flow, the big file

> Continued in
> [2026-11-02-carplay-video-request.md](2026-11-02-carplay-video-request.md)
> — the CarPlay video request itself: the package for the Apple account admin, the
> one-category-per-app fix and `scripts/carplay_grant.sh`.

## What was asked

"ok then fix all remaining" — close every item the review had left open:

1. the CarPlay video entitlement,
2. the CarPlay attach to the Simulator,
3. the `http://` provider that App Transport Security now blocks,
4. automatic testing,
5. the Pro product decision (product id, paywall, reachable purchase path),
6. the 2,022-line `CarPlayVideoViewController.swift`.

## What was done

| # | Item | State |
|---|---|---|
| 1 | CarPlay video entitlement | **Done** (the code asks for it; Apple still has to grant it) |
| 2 | CarPlay attach | **Needs the user** — one click in Xcode's Device Hub, there is no command line for it |
| 3 | Public-IP `http://` | **Done** — the app now says what went wrong instead of failing silently |
| 4 | Automatic testing | **Done** — one script + a GitHub Actions workflow |
| 5 | Pro flow | **Done** — the paywall is reachable, the product has an id, the purchase path can be tested without a Sandbox account. **What Pro unlocks is still the developer's call** |
| 6 | The 2,022-line file | **Done** — split by responsibility |

### 1. The CarPlay video entitlement

The entitlement key is **`com.apple.developer.carplay-video`** — not `com.apple.developer.carplay`.
`CarTV.entitlements` now asks for it next to `com.apple.developer.carplay-audio`.

Apple grants that capability per app, and it cannot be self-enabled:

1. Apple Developer → **Certificates, Identifiers & Profiles** → *Identifiers* → the app id
   → **CarPlay** → request the **Video** category.
2. Apple reviews the request (a demo of the app playing video in the car).
3. Regenerate the provisioning profile (Xcode: *Signing & Capabilities* → *Manage Profiles*).
4. Build for the device.

**Until the profile carries the entitlement the device build stops signing.** That is the
expected state of a CarPlay video app, not a bug. The Simulator build is unaffected — it
does not check the profile.

### 2. The CarPlay attach

The CarPlay Simulator app is installed (`~/Desktop/CarPlay Simulator.app`) and running, and
the device kit plugin is in Xcode. The attach itself is a UI action:

- Xcode → the **Devices** button in the toolbar (the icon next to the Run button) →
  *Device Hub* → the attached peripheral **CarPlay Simulator** → pick **DrivePlay**.

There is no command line for it: `simctl` has no CarPlay subcommand, `devicectl` has no
session subcommand, and the CarPlay Simulator app declares no URL scheme. What *can* be
checked from the shell is the result — the app logs `DRIVEPLAY CarPlay scene connected` when
the scene connects:

```bash
xcrun simctl spawn booted log show --last 5m --style compact \
  --predicate 'process == "CarTV"' | grep DRIVEPLAY
```

At the time of writing the log shows only the window-scene role, i.e. the car screen has
not been attached yet.

### 3. A blocked `http://` server now explains itself

App Transport Security refuses an unencrypted public address with a system error that does
not say what to do. `URLPolicy.message(for:)` now turns that one error into "iOS blocked
this address because it uses an unencrypted connection (http://). Use https:// — or, for a
server on your own network, its local address." Every source-add path uses it.

### 4. Automatic testing

- `scripts/run_tests.sh` — the whole suite, with the ad-hoc signing the Keychain needs and
  an automatic choice of Simulator (`SIMULATOR=…` overrides it).
- `.github/workflows/tests.yml` — generates the project and runs the same script on every
  push. **It does nothing until the folder is a git repository and is pushed** — this
  project is not under version control yet.

While doing this, the scheme turned out to be broken: it was defined under a *target* in
`project.yml`, which XcodeGen does not write to disk. No `.xcscheme` existed, so Xcode
silently used an auto-created scheme — without the test target, and without anything else
the project asked for. The scheme is now defined at the project level and lives in
`CarTV.xcodeproj/xcshareddata/xcschemes/CarTV.xcscheme`.

### 5. The Pro flow

- `Configuration/DrivePlay.storekit` — a local StoreKit configuration with the Pro product
  (`com.rushabh.cartvv.pro`, `4.99`), attached to the scheme's Run action. The purchase
  path can be exercised in the Simulator without a Sandbox account.
- The paywall is now reachable from **Settings → DrivePlay Pro**, and it says which state it
  is in: unlocked, upgrade available with its price, or not in the store yet.

**What Pro unlocks is still not decided, and nothing is gated behind it.** The app ships
with every feature free. Before selling it: decide what Pro unlocks, create the product
with the id `com.rushabh.cartvv.pro` in App Store Connect, and wire the gates. A purchase
button that unlocks nothing is a problem in review.

The app's own earlier StoreKit file (found inside the last installed build) offered
**Weekly Pro 3.99**, **Yearly Pro 45.99** and **Lifetime Pro 27.00** under the ids
`com.cartv.pro.*`, and described Pro as "unlimited sources, Car Mode, and unlimited
casting". The code now uses the single id `com.rushabh.cartvv.pro` (which matches the
bundle id) at the same 27.00 price. Pick one set of ids before creating the product.

### 6. The 2,022-line file

`CarPlayVideoViewController.swift` was split by responsibility:

| File | Lines |
|---|---|
| `CarPlayVideoViewController.swift` (class, enums, properties, lifecycle) | 216 |
| `+TopBar` | 94 |
| `+Content` | 256 |
| `+Browser` | 541 |
| `+Video` | 101 |
| `+Mirror` | 82 |
| `+Search` | 121 |
| `+Shelves` | 331 |
| `+Actions` | 318 |

The code was **moved, not rewritten**. Swift's `private` only reaches one file,
so the 63 stored properties and the methods the extensions share were widened
from `private`/`fileprivate` to internal (nothing became `public`).

The move was verified mechanically: the pre-split file was recovered from the
session log and compared with the nine new files — every line of the original
body is present, unchanged apart from the intended visibility widening (the
only lines "missing" are the five `import` statements, which now sit in the
files that need them).

## Verification

```
scripts/run_tests.sh
→ Executed 48 tests, with 0 failures  ** TEST SUCCEEDED **
```

The app builds, installs and launches on the Simulator (`iPhone 18 Pro`); the
home screen renders with `GPS SAT-LOCK: ACTIVE`.

## What the user still has to do

1. Request the CarPlay **video** capability from Apple and regenerate the profile — until
   then the device build stops signing. **The request package is ready:**
   [2026-11-02-carplay-video-request.md](2026-11-02-carplay-video-request.md) has the
   step-by-step guide for the Apple account admin.
2. Attach the CarPlay Simulator in Xcode's Device Hub (one click, see above).
3. Create the Pro product in App Store Connect and decide what it unlocks.
4. Push the project to a git repository, or the CI workflow stays inert.

## Files changed

```
CHANGELOG.md                                     (the ATS message, the entitlements, the scheme, the split, the new tooling)
AGENTS.md                                        (the CarPlay entitlements, the shared-scheme rule, the StoreKit configuration)
docs/SPEC.md                                     (AC25, AC26, the new verification command)
docs/handoffs/2026-11-02-carplay-…               (new: this file)
.gitignore                                       (new: secrets, Xcode and macOS noise)
scripts/run_tests.sh                             (new: the whole suite in one command)
.github/workflows/tests.yml                      (new: CI)
Configuration/DrivePlay.storekit                 (new: the local StoreKit configuration)
CarTV/Resources/CarTV.entitlements               (the CarPlay video entitlement)
CarTV/Sources/Services/URLPolicy.swift           (the message for a blocked address)
CarTV/Sources/Services/PlaylistStore.swift       (uses that message)
CarTV/Sources/Views/Settings/SettingsView.swift  (the Pro row)
CarTV/Sources/Views/Settings/ProPaywallView.swift (the state of the upgrade)
CarTV/Tests/URLPolicyTests.swift                 (AC25)
CarTV/Tests/StoreKitConfigurationTests.swift      (new, AC26)
CarTV/Sources/Views/CarPlayVideoViewController*.swift (the split, 9 files)
project.yml                                      (the shared scheme, the StoreKit configuration)
CarTV.xcodeproj/xcshareddata/xcschemes/CarTV.xcscheme (new: the shared scheme)
```
