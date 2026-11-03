# Handoff — the crash fix is verified on the car; video is one click away (2026-11-03)

Follows `2026-11-03-carplay-presenttemplate-crash-fix.md` (the fix) and
`2026-11-02-carplay-presenttemplate-crash.md` (the wrong root cause).

## 1. The crash fix holds on the car

The phone (iPhone 13, iOS 27, `00008110-001C60423CB8401E`) was connected, the
CarPlay Simulator in Xcode 27 was attached to it, and DrivePlay's CarPlay
scene ran on the car:

```
2026-11-03 11:07:41.086 CarTV[15457] DRIVEPLAY CarPlay scene connected
```

A category was tapped, a channel ("4ever Cinema (1080p)") was selected, the
channel played on the car, and **the app survived**: the process was still
alive afterwards (`devicectl device info processes` → pid 15521) and the
console shows no `Terminating app`, no exception, no SIGABRT. The earlier
instance exited with `exit code 0` — a clean exit, not a crash.

The car's now-playing screen shows the app's own metadata (title, "Movies",
the generated artwork card) and the transport controls work.

**The template renders too**: the car's root template lists *Screen Mirroring*,
*Categories* (Movies 854, Series 384, Sports 453, News 973, …) and a
*Search* button. So the `CPListTemplate` path works end to end.

## 2. Video: the only blocker is the provisioning profile

Apple **already granted** the CarPlay Video App entitlement to the team
(Case-ID 23260500, App Type VIDEO — see `docs/carplay-video-request.md`). The
capability is *editable* on the app id, but the app id in the portal still
carries **CarPlay Audio**, so the only local profile for the app id carries
`com.apple.developer.carplay-audio` and nothing else:

```
PROFILE: iOS Team Provisioning Profile: com.rushabh.cartvv
  appid=47T499AR2T.com.rushabh.cartvv
  carplay_keys=carplay-audio
```

`CARPLAY_CATEGORY=video ./scripts/carplay_grant.sh grant` therefore fails:

```
error: No Accounts: Add a new account in Accounts settings.
error: Entitlement com.apple.developer.carplay-video not found and could not be
       included in profile.
```

Two things are needed, and **only the account holder can do them**:

1. **Xcode needs an account** — `xcodebuild -allowProvisioningUpdates` cannot
   reach the portal without one ("No Accounts"). It did have one when the
   capability was first measured; it does not now.
2. **The app id has to be flipped** in
   <https://developer.apple.com/account/resources/identifiers/list> →
   *XC com rushabh cartvv* → *Capabilities* → **CarPlay Video on, CarPlay
   Audio off** (both at once is not supported) → *Save*.

After that, one command signs the video build:

```bash
CARPLAY_CATEGORY=video ./scripts/carplay_grant.sh grant 00008110-001C60423CB8401E
```

The code needs no change: `CarPlayCategory` in the Info.plist is
`$(CARPLAY_CATEGORY)`, `isEntitledToVideo` reads it, and every row then
carries `preferredPresentation: .video` — which is the signal that makes the
system draw the picture itself.

## 3. Why there is no way around the entitlement

* The entitlement check is on the **device** (the phone runs CarPlay), not on
  the head unit: *"presentation is video but app does not have the video
  entitlement"*.
* A **simulator** build can carry the entitlement without a profile (it lives
  in the Mach-O), but **the CarPlay Simulator in Xcode 27 hosts physical
  devices only** — its *Sessions* menu lists the iPhone and nothing else, even
  with the iPhone 18 Pro simulator booted. So the embedded-entitlement build
  can never reach this car.
* A profile cannot be forged; only Apple can mint one with the entitlement in
  it, which needs portal access.

### Proven on the device, not just read in a header

The phone's installer was made to judge a video-signed build directly. The
app was re-signed with `com.apple.developer.carplay-video` in its
entitlements, keeping Apple's own audio profile embedded, and installed:

```
xcrun devicectl device install app --device 00008110-… <app>
→ Failed to verify code signature … 0xe8008015
  (A valid provisioning profile for this executable was not found.)
```

The same error came back with **both** certificates in the keychain, so it is
not a certificate mismatch: the installer refuses any entitlement the
embedded profile does not cover. Apple's installer enforces entitlement
coverage, so the video entitlement has to be inside a profile **Apple issued**
— and Apple only issues one for an app id whose CarPlay capability is set to
*video*.

That is why "both categories are approved" is not yet "both work": the
approval is on the **team**, the switch has to be flipped on the **app id**
(*XC com rushabh cartvv* → Capabilities → CarPlay Video on, CarPlay Audio
off) and the app's profile has to be regenerated from that.

## 4. Other things measured today

* **The phone carries two apps**: the old `CarTV com.lyntra.player 1.1.6`
  (green icon) and ours, `DrivePlay com.rushabh.cartvv 1.2.0` (dark icon with
  the play triangle). The car's Automaker UI grid showed the old one and three
  system apps; DrivePlay was not in that row, but it is reachable (the
  template renders), so the grid is not the gate.
* **`devicectl device capture screenshot --destination <file>.png`** works on a
  physical device (`--output` is not a valid flag).
* **The CarPlay Simulator's session dies with the USB connection.** Its
  windows disappear (the *Window* menu still lists them, but the AX window
  list is empty) and the app has to be restarted. It also failed on its own
  today: `AirPlay Session Failed ... Reason: -10879` → the CarPlay scene
  disconnected 17 s after it connected.
* **Driving the car display safely**: verify with
  `NSWorkspace.frontmostApplication` that *CarPlay Simulator* is really
  frontmost **immediately before** posting the `CGEvent`. A blind click lands
  in whatever the user has open — two clicks went into the user's Teams chat
  and Chrome during an earlier session. The helper that does this is
  `/tmp/cpclick.js` (raise → verify → click → capture), and it aborts with
  `NOT-FRONTMOST <app>` rather than clicking.

## 5. Verification

```bash
./scripts/run_tests.sh     # 67 tests, 0 failures
```

## 6. Still open

* The video build — waiting on the account (section 2).
* **The broadcast still needs one tap by the user on the phone**: DrivePlay →
  *Screen Mirroring* → the broadcast button → *DrivePlay Screen Relay*. iOS
  27 marks the whole ReplayKit broadcast family "no longer supported" except
  the picker, so the upload extension may not launch any more.
* `git init` + a first commit — the project is **not** a git repository, so
  none of this work is version-archived yet.
