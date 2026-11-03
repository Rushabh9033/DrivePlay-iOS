# Handoff — 2026-11-02 — the CarPlay video request (package for the account admin)

> Continued in this file from
> [2026-11-02-carplay-entitlement-testing-and-pro-flow.md](2026-11-02-carplay-entitlement-testing-and-pro-flow.md).
> The entitlement itself is still Apple's to grant; this session prepared the request
> and fixed the project so it can use the grant.

## What was asked

"ok now do the apple carplay video request steps for me", then: a step-by-step guide
for the **admin of the Apple account**, because the developer does not have access to
the account that owns the team.

## Where the request actually stands

The request form (<https://developer.apple.com/contact/carplay/>) is behind the Apple ID
sign-in and it includes the **CarPlay Entitlement Addendum**, which only the Account
Holder can accept. The browser in this session has no Apple session (and no Chrome
profile with one exists on this machine), so the submission is the account admin's
step. Everything around it is done.

## What was found in Apple's own documentation

- **CarPlay Developer Guide** (October 2026), appendix *Entitlements*:
  `com.apple.developer.carplay-video` is the video category's key and it needs **iOS 27**.
  The key in `CarTV.entitlements` was right.
- *"Multiple categories cannot be combined in a single app"* (same guide) — so the
  entitlements file asking for **both** `carplay-audio` and `carplay-video` asked for two
  categories and could never be granted. It now asks for the video category only.
- Video-app guidelines: the app must be designed primarily for video playback and must
  support AirPlay video streaming. DrivePlay qualifies: `AVPlayerViewController` (system
  AirPlay button) plus an `AVRoutePickerView` in the Cast tab. Caveat: raw MPEG-TS
  streams (`http://…/channel.ts`) do not travel over AirPlay — HLS does.
- Each category may only use the templates in the guide's matrix (page 15); an
  unsupported template throws at runtime. The app uses list, now-playing and search.
- The request is granted as a **managed capability** on the team; the App ID then gets
  the capability enabled in *Identifiers → App ID → Additional Capabilities → CarPlay*,
  and the profile has to be regenerated.

## What was done

| # | Item | State |
|---|---|---|
| 1 | The request package for the account admin | **Done** — `docs/carplay-video-request.md` |
| 2 | The entitlements file asks for one category | **Done** — video only |
| 3 | A helper that checks the profile and fetches a new one | **Done** — `scripts/carplay_grant.sh` |
| 4 | Tests for both | **Done** — AC27, AC28 |
| 5 | The request itself | **Needs the account admin** — sign-in + addendum |

### 1. `docs/carplay-video-request.md`

The guide the admin can follow: sign in, open the form, the text for every field
(app name, bundle id, category, app description, the content-rights answer), the demo
video to send if Apple asks for one, how to accept the addendum, and what to do if it
is rejected. Nothing technical is left to the admin.

### 2. One CarPlay category per app

`CarTV.entitlements` asked for `carplay-audio` **and** `carplay-video`. Apple grants one
category per app, so the file could never be signed for a device. It now asks for
`com.apple.developer.carplay-video` only. If the team applies for the **audio** category
instead (older cars, no iOS 27 needed, an audio app may also play video), the key is one
line away — and it is the only other category that fits this app.

### 3. `scripts/carplay_grant.sh`

```bash
scripts/carplay_grant.sh check      # does a local profile carry the entitlement?
scripts/carplay_grant.sh grant      # ask Xcode for a new one that carries it
```

`check` reads the entitlement from the entitlements file (not a copy), finds the app's
profiles in the two local profile folders and prints `OK`/`MISSING` per key.
`grant` detects the connected iPhone from the build destinations and rebuilds with
`-allowProvisioningUpdates`, which is how the new profile and the missing signing
certificate are created, then prints the entitlements of the signed app.

Right now it prints:

```
MISSING  com.apple.developer.carplay-video — no local profile carries it (Apple has to grant it first)
```

### The device build, run against the real phone

With the iPhone 13 connected (`00008110-001C60423CB8401E`), the grant script was run for
real. It stops exactly where it should — before compiling, at the provisioning step:

```
/Users/radhikamac/carTv-iptv/CarTV.xcodeproj: error: Entitlement
com.apple.developer.carplay-video not found and could not be included in profile.
This likely is not a valid entitlement and should be removed from your entitlements file.
** BUILD FAILED **
```

That is the expected state — the key is correct (Apple's CarPlay Developer Guide lists it
for the video category), the account has not been granted it yet. Nothing else is missing
on this side: the certificate for the team and the profile are created by the same
command once Apple has granted the capability.

**The CarPlay Simulator attach is behind the same grant**: without a CarPlay entitlement
the app does not appear on the car screen at all, so the Device Hub test has to wait for
the grant as well.

## Verification

```
scripts/run_tests.sh
→ Executed 50 tests, with 0 failures  ** TEST SUCCEEDED **
```

`scripts/carplay_grant.sh check` runs and reports the state above.

## What the account admin has to do

The step-by-step guide is in `docs/carplay-video-request.md` — the short version:

1. Sign in to <https://developer.apple.com/account/> with the Account Holder's Apple ID.
2. Open <https://developer.apple.com/contact/carplay/>.
3. Fill the form with the text from the guide (category **Video**, bundle id
   `com.rushabh.cartvv`, app name **DrivePlay**).
4. Accept the **CarPlay Entitlement Addendum** and submit.
5. Send a short screen recording of the app in the car if Apple asks for a demo.

Nothing else — the capability, the profile and the build are this side.

## Files changed

```
docs/carplay-video-request.md                    (new: the guide for the account admin)
docs/carplay-video-request-simple.html            (new: the plain-language guide, print source)
docs/carplay-video-request-simple.pdf             (new: the plain-language guide as a PDF)
scripts/carplay_grant.sh                         (new: check / grant the entitlement)
CarTV/Resources/CarTV.entitlements               (one CarPlay category: video)
CarTV/Tests/CarPlayEntitlementTests.swift        (new, AC27 + AC28)
docs/SPEC.md                                     (AC27, AC28, the non-goal)
AGENTS.md                                        (one category per app, the iOS 27 rule, the helper)
CHANGELOG.md                                     (the entitlements, the helper, the guide, 48 → 50 tests)
```
