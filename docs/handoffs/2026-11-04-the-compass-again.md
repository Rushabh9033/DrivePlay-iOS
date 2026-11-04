# Handoff — the compass, again (2026-11-04)

## The request

> *"compass still not working properly and its not smooth"*

The previous round fixed the rose's sign, the needle's place and the course's
priority. The compass was still wrong and still jumped. This round is the
rest of it.

---

## 0. A wrong conclusion of my own, first

I concluded that **`didUpdateHeading` never fires on the phone** — no
callback, no log line. That conclusion was **wrong**, and it came from a
**broken capture**: `idevicesyslog` had printed *"Waiting for device with
UDID … to become available"*, exited, and written **three** lines. A
three-line capture cannot prove a callback is absent.

The same capture did hold two `didUpdateHeading` entries, and
`xcrun devicectl device process launch --console` shows the compass working
outright:

```
DRIVEPLAY compass: the heading updates are on
DRIVEPLAY compass: heading 266°, rose -266°
```

**Lesson (in `AGENTS.md`):** a capture is evidence only when it has content.
Check the line count before believing what is missing from it.

---

## 1. The heading was out by 27° and was shown as a direction

The device's own log line is the ground truth:

```
didUpdateHeading: magneticHeading 266.75 trueHeading 267.05 accuracy 27.58
                   headingMode 0 x +32.265 y -19.425 z -7.843
```

`headingAccuracy` is the heading's **error**, and 27.58° is not a direction.
A phone lying flat has no usable horizontal field to read a heading from, so
the error grows into the tens of degrees — and a needle that follows such a
reading points the wrong way, which is **worse** than the GPS's course.

- A reading the compass is out by more than **twenty degrees** is refused.
- The GPS's **course** takes over (it is already the fallback for a device
  without a compass — now it is the fallback for a compass that has lost its
  certainty as well).
- The panel says **GPS COURSE** instead of **HEADING** / **BEARING** while
  the compass is not sure, so the user knows which one they are looking at.

**AC147**, **AC149**.

Note what the same two lines say about the *noise*: the readings were
**1.06°** apart. The noise is small, the **error** is large — a filter cannot
fix that one, only a gate can.

## 2. The smoothing counted readings, not seconds

"Close a third of the gap per reading" is not a filter: the magnetometer
delivers several times a second and the GPS once a second, so it smooths one
of them and not the other.

And CoreLocation delivers in **bursts** — the two readings above were
*measured* a second apart and handed over **128 ms** apart, so the needle
took two steps in a fraction of a second. That is the jolt the user called
"not smooth".

The filter now runs on a **clock**:

```swift
let fraction = 1 - exp(-elapsed / Self.smoothingTimeConstant)   // τ = 0.6 s
```

so the needle moves by how much **time** has passed, and the same readings
move it much less when they arrive together.

The clock is the moment the reading **arrived**, not the reading's own stamp
— what the user sees is when the needle moved, not when the field was
measured — and it only ever moves **forward**. A reading that arrives late
(a buffered one whose own stamp is older than the reading already applied)
no longer moves the needle and no longer drags the clock back, which would
make the next reading close a gap that never happened.

The seam takes the **arrival** time for exactly this reason — a test that
cannot drive the clock cannot pin this down.

**AC143**, **AC148**.

## 3. A red needle said "north" while the letters said something else

The needle is **fixed** (it points the way the car faces) but it was painted
like a *magnetic* compass's needle — red for north — so it pointed up for
ever while the rose turned under it, and the rose's own red **N** went round
the dial. Two north markers that disagree is what "shows completely wrong
direction" meant.

The dial is a **heading indicator** now: the card turns, one green marker
stays at the top, and red is the card's **N** alone. Both compasses (the
cockpit and the phone's cluster) were changed the same way.

## 4. The rose spun the long way round at north

The rotation was wrapped into `0..<360`, so every time the heading crossed
north the rose turned **358°** backwards. The rotation is continuous now.

**AC144**.

---

## What the tests cover

| AC | What it pins |
|---|---|
| 143 | The heading is smoothed — the display moves toward the new heading |
| 144 | The rose does not spin when the heading crosses north |
| 145 | A compass that does not know (−1) is refused, and the course survives |
| 146 | The course is only used while the car is **moving** |
| 147 | A compass that is not sure of itself does not steer the needle |
| 148 | The heading is smoothed by **time**, not by the number of readings |
| 149 | The compass says whether it is sure of the heading |

`docs/SPEC.md` now carries **149** acceptance criteria and
`CarTV/Tests/` carries a test for each one — the two sets are the **same
set**, checked mechanically.

### What has actually been run

| Check | Result |
|---|---|
| `xcodebuild … -destination generic/platform=iOS build-for-testing` | **TEST BUILD SUCCEEDED** |
| The compass code, executed | the **real** `SatelliteHUDService.swift` compiled into a standalone program (only the `import UIKit` line and one macOS-unavailable call in `stop()` removed) and driven through the assertions of AC135–AC149 — **28 checks, all green**. Against the *old* clock behaviour the same harness fails the late-reading check (86.79° instead of 73.0°), so the check bites |
| The device suite (the whole 165-test suite on the phone) | **queued** — the phone is off the USB bus |

---

## 5. The security review the hook could not finish

The **automated** commit-time security review **timed out** on this tree (the
hook's own log: *"The read operation timed out"* and *"the model's reply
could not be read"*), so the commit was **not marked reviewed**. The review
was run by hand over the whole uncommitted diff instead.

Three findings were **fixed**:

| What | Where | Why it mattered |
|---|---|---|
| The stream's token was **32 bits** (`prefix(8)` of a UUID) | `Shared/LiveScreenStream.swift` | The stream is the phone's screen, served over the local network; the token in its path is the only lock on it. 2³² guesses is a weekend's work for anyone on the same Wi-Fi. **128 bits** now (**AC150**) |
| A failed stream logged the account's **token** | `PlaybackManager.swift` | `String(describing: itm.error)` puts the failing URL — and Plex's `X-Plex-Token`, Jellyfin's `api_key` and Xtream's password — into the device's log, which anything attached to the phone can read |
| The browser logged the **URL the user typed** | `BrowserTabManager.swift` | A pasted `https://user:password@host/` is a password in the log |

Both leaks now go through one helper, `CredentialRedactor.safeForLog(_:)` in
`CredentialStore.swift`: it keeps the **host and the file name** and drops the
user info, the query and every path segment but the last (Xtream keeps the
user and the password there). The redaction was executed against the repo's
own file: `http://example.com/12345.ts` — no password, no token, no user
name (**AC151**).

Three findings are **written down instead**, with the reason — they are in
§1.24 of `docs/review-2026-11-03.md` and in §5 of the same document:

1. the **relay's control channel** (loopback port 47311) is unauthenticated,
   and the app and the extension share no secret — closing it needs an App
   Group (another Apple-granted capability) or the user's confirmation;
2. a source whose secrets the **Keychain refuses** is written to
   `UserDefaults` in the clear — a deliberate, documented fallback;
3. **neither web view has a navigation policy** — the scheme is constrained
   where the address is entered, but a redirect is not checked.

---

## What was not touched

- The **iPhone 18 Pro simulator** was never booted. Every build was made
  against `generic/platform=iOS` (which compiles without running anything)
  and the physical iPhone 13 (`00008110-001C60423CB8401E`).
- `scripts/carplay_simulator.sh` was not run.
- The CarPlay **entitlements** and the provisioning profile were not changed.

## Where the code is

| What | Where |
|---|---|
| The compass | `CarTV/Sources/Services/SatelliteHUDService.swift` |
| The cockpit dial | `CarTV/Sources/Views/CarMode/SatelliteHUDView.swift` |
| The phone's cluster dial | `CarTV/Sources/Views/Home/DigitalClusterCardView.swift` |
| The compass's tests | `CarTV/Tests/SatelliteHUDTests.swift` |
| The log redaction | `CarTV/Sources/Services/CredentialStore.swift` (`CredentialRedactor.safeForLog`) |
| The stream's token | `Shared/LiveScreenStream.swift` |

## Still open

- **The phone dropped off the USB bus** while this round was being finished.
  Right now `xcrun devicectl list devices` shows *Rushabh's Iphone* as
  **unavailable** — it is not on the bus at all, and `devicectl device info
  lockState` fails with *"The tunnel connection failed"*. The device suite for
  this round is **queued**: the first waiter's 100-minute window expired with
  the phone still gone, so a **24-hour** waiter is running now — it polls every
  15 s and writes `build/device_test_compass.log` the moment the phone
  answers, so it runs on its own. It also **waits out a locked phone**: a
  locked screen cannot launch the test bundle (*"Xcode cannot launch
  CarTVTests … because the device is locked"*), so the run is retried every
  30 s, eight times, instead of reporting a failure the user has to fix by
  hand. The compile check (`TEST BUILD SUCCEEDED`) passed and the compass code
  was executed on its own (see the table above). **Replug the cable** and the
  suite will run by itself.
- **The round is committed** as `53bfdbe` ("The compass that was still wrong,
  and the locks that were too small") on `main`, **locally only** — this
  repository has **no remote**, so nothing was pushed.
- `AGENTS.md`'s *Build & test* section now carries the user's own rule — the
  **physical iPhone 13 only**, the iPhone 18 Pro simulator never booted,
  `generic/platform=iOS` for a compile check — so the next session cannot
  repeat the mistake.
- **AC32 fails on the phone with a SIGKILL** — pre-existing, reproducible on
  its own, and it failed on 3 November before any of this round's code
  existed. There is **no crash report**; the device's own log shows a
  FrontBoard **watchdog** kill (*"Failed to terminate gracefully after 5.0s"*,
  `WatchdogEvent: process-exit`). A kill, not a crash — the same shape as the
  locked-phone failures in `AGENTS.md`.
- The compass reads the **phone's** magnetometer. In a real car the car's own
  compass is the better source, and iOS does not hand it to a CarPlay app.
