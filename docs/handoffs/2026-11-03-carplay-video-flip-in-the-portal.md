# Handoff — the CarPlay video flip is done in the portal; one file away from the picture (2026-11-03)

> **Update, later the same day:** the missing file was minted. The profile for
> `com.rushabh.cartvv` now carries **both** `carplay-audio` and `carplay-video`,
> and the device build signs with both — see
> `2026-11-03-carplay-four-tab-redesign-and-car-switch.md`. Section 2 below
> describes the state *before* that profile existed.

Follows `2026-11-03-carplay-verified-on-the-car.md` (the crash fix, verified on
the car). The blocker there — "the video surface needs a provisioning profile,
and a profile needs the portal" — is now one half done.

## 1. What changed in the portal

The account holder flipped the app id **XC com rushabh cartvv**: *CarPlay
Video* ON, *CarPlay Audio* OFF, and saved it. That is the switch the earlier
handoffs said was the whole job.

Apple's grant was already in place (Case-ID 23260500, App Type VIDEO), so the
team can now mint a profile that carries `com.apple.developer.carplay-video`.

## 2. What is left — one file

The **profile** is the app id's capabilities frozen into Apple's signature, so
the profile that was minted before the flip still says `carplay-audio`. It has
to be minted again:

* Profiles → *+* → **iOS App Development** → App ID **XC com rushabh cartvv** →
  certificate **Florence Mitchell (U6QAPJYF45)** → name **DrivePlay Video** →
  Generate → Download.

The certificate matters: it is the only one in this Mac's keychain
(`security find-identity -v -p codesigning` lists two — *rushabhmavani01@gmail.com*
and *Florence Mitchell* — and the existing profiles name the latter). A profile
with the other certificate does not sign here.

Then:

```bash
scripts/carplay_video_install.sh            # finds the profile in ~/Downloads
scripts/carplay_video_install.sh <file>     # or names it
```

The script finds the profile **by its contents** (it must carry
`com.apple.developer.carplay-video` for `47T499AR2T.com.rushabh.cartvv`), not
by its name, so any name works. It installs it where Xcode looks, moves the
audio profile it replaces aside, builds with `CARPLAY_CATEGORY=video`, checks
that the app really was signed with `carplay-video`, and installs it on the
phone.

## 3. Signing works without an account — measured

The earlier handoffs said the build needed an Apple account on this machine
(`xcodebuild` says "No Accounts"). **That is only true of
`-allowProvisioningUpdates`**, which asks the portal for a profile. Automatic
signing works **offline**: with a matching profile in
`~/Library/Developer/Xcode/UserData/Provisioning Profiles`, this build machine
(no account in Xcode) signs the device build fine:

```
xcodebuild … -destination "id=00008110-…" CARPLAY_CATEGORY=audio build
** BUILD SUCCEEDED **
```

The app was signed with `com.apple.developer.carplay-audio`, the extension with
the **wildcard** profile — the app's own profile does *not* cover
`com.rushabh.cartvv.ScreenRelay` (Xcode wants an exact match).

## 4. Three bugs fixed in the broadcast chain

The phone's screen on the car runs through the broadcast extension → a local
HLS server → the app's own player. Three bugs sat in that path; all three are
fixed and each has a test (AC46–AC48).

| Bug | Symptom | Fix |
|-----|---------|-----|
| The fragment window was **read** under a lock and **written** without one | A Swift array mutated while it is read — undefined behaviour, not a glitch | The fragments are filled and read under the same lock |
| A broadcast address that arrived **in two pieces** was dropped | The first read held half an address, which is not an address, and the extension does not send it again — the phone's screen never reached the car, silently | The listener waits for the whole line |
| A relay that **could not listen** said nothing | The bind fails after `start()` returned, so the app waited forever for an announcement that could not arrive | The failure is reported and the app says so |

The relay's failure path needed a seam, so `ScreenRelayListener` takes the
port and `ScreenShareService` takes the relay. Both are internal — the public
API is unchanged.

## 5. Verification

```bash
scripts/run_tests.sh     # 70 tests, 0 failures
```

## 6. Still open

* **The profile** (section 2) — the account holder's one action.
* **The picture on the car.** Even with the profile, a CarPlay **video** app
  only appears on the car's home screen **if the head unit supports "video in
  car"** (WWDC26 session 212, "Rev up your CarPlay app"), and the channel's
  stream has to carry a video track. The CarPlay Simulator is a stand-in for
  the head unit, so it will show what the app plays.
* **The broadcast on iOS 27.** The chain is finished and tested, but iOS 27
  marks the whole ReplayKit broadcast family *"No longer supported"* except the
  picker, so the upload extension may not launch any more. One tap by the user
  on the phone answers it: DrivePlay → *Cast to Car* → the broadcast button →
  *DrivePlay Screen Relay*.
* `git init` + a first commit — the project is **not** a git repository, so
  none of this work is version-archived yet.
