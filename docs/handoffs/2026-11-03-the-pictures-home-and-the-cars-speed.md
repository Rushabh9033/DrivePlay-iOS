# Handoff — the picture's home, and the car's speed (2026-11-03)

## The defects this pass answers

1. *"video sometimes only play in car sometimes only in mobile"* — the picture
   was on **neither** screen when the car was not ready for it.
2. *"switching from car to phone and phone to car has so many issues"* —
   taking the picture back did not bring the phone's own picture back, and the
   picture jumped back to the car a few seconds later on its own.
3. *"2 laggy not buttry smoothness"* — the phone stuttered while a video
   played, and the car's screen was slow.
4. *"make responsive"* — the **car's CarPlay screen** (the user chose the car,
   not the phone).

## 1. The picture's home belongs to the system

The hand-off hid the phone's picture the moment it was asked for, and the car
only takes the picture when the **system** says so (`isExternalPlaybackActive`,
KVO). The car's video endpoint arrives minutes after the scene connects, so
there was a long window in which the phone had already given its picture up
and the car had not taken it: the video was on **neither** screen.

`PlaybackManager` now keeps the picture where the **system** says it is:

| State | Who decides | What the phone shows |
|-------|-------------|----------------------|
| the app asks for the car | the app (the intent) | the picture, until the system answers |
| the system reports the picture on the car | the system | no picture of its own — the output follows |
| the user takes it back | the user | the picture, at once |
| the car disconnects | the app (the car is gone) | the picture, at once |

* `systemSaysPictureIsOnCar(_:)` is the **only** place the answer is acted on,
  and `isPlayingOnCar` is `@Published public private(set)` — the flag had two
  writers (the app and the KVO) and the banner flickered.
* Every hand-off and every picture taken back gets a new **generation**
  (`handOffGeneration`), so the ladder that offers the picture again stops at
  once. Without it the picture jumped back to the car on its own (AC108).
* `castToPhone()` restores the phone's picture (`presentationMode =
  phonePresentationMode`), which it never did before.
* `carDisconnected()` hands the picture back to the phone, so a car that goes
  away does not leave a black screen.
* The switch says **"Sending to Car…"** while the picture is on its way —
  the tap used to look like nothing had happened.

## 2. The stutter

`updateNowPlayingInfo()` ran four times a second (the periodic time
observer) and **drew the artwork** every time: a 512×512 gradient, a symbol
and three lines of text, on the main thread. The artwork is drawn once per
channel and kept now, and the info is only handed over when something in it
changed — the system counts the seconds itself once the rate is known (AC109).

A video that has just started was also offered to the car **twice**: the item
had been attached with the route already open, and the hand-off offered it
again straight away, which builds the player a second time. The offer is not
made again at the start (AC110), and the player's flags are set **before** the
item is attached — the system looks at the route when the item arrives.

## 3. The car's screen

Three separate causes, all measured on the phone:

| What | Before | After |
|------|--------|-------|
| The Home tab **built** (13 sections, 44 cards) | 65 ms | **48 ms** — never the bottleneck |
| Eight pictures from **eight servers** | 1.6 s | **18 ms** |
| The car told about a row of **eight** pictures | eight reloads of the row | **one** reload for the batch |

* the gap between logo requests is **per host**: it exists because of one
  CDN's per-IP quota, and that quota belongs to the server (AC105);
* the card patches go out **in batches** (`CarPlayCardPatcher`): a logo that
  arrives patches the card that shows it, but the **row** is handed to the car
  again, and a row carries every card in it (AC106).

## The criteria this pass added

| AC | Criterion | Test |
|----|-----------|------|
| 104 | The car's Home tab is built in a moment | `CarPlayResponsivenessTests` |
| 105 | The pictures of different servers arrive together | `CarPlayResponsivenessTests` |
| 106 | The car is told once for a batch of pictures | `CarPlayResponsivenessTests` |
| 107 | The picture is never on neither screen | `PlaybackManagerTests` |
| 108 | The picture taken back does not jump back to the car | `PlaybackManagerTests` |
| 109 | The now-playing artwork is drawn once per channel | `PlaybackManagerTests` |
| 110 | A video that has just started is not offered to the car twice | `PlaybackManagerTests` |

**AC54, AC64 and AC103 were rewritten** — they encoded the old timing (the
phone gives its picture up the moment it asks). The criterion is the same; the
moment is now the system's answer.

## Files touched

| File | What changed |
|------|--------------|
| `CarTV/Sources/Services/PlaybackManager.swift` | the picture's home (the intent, the generation, `systemSaysPictureIsOnCar(_:)`, `carDisconnected()`), the cached now-playing artwork, the flags set before the item is attached |
| `CarTV/Sources/Views/Player/CarOutputSwitch.swift` | the **"Sending to Car…"** state |
| `CarTV/Sources/App/CarPlaySceneDelegate.swift` | `carDisconnected()` on the scene's disconnect |
| `CarTV/Sources/Views/CarMode/CarPlayArtwork.swift` | the request gap is **per host** |
| `CarTV/Sources/Views/CarMode/CarPlayTabs.swift` | `CarPlayCardPatcher` — the car is told once per batch |
| `CarTV/Tests/PlaybackManagerTests.swift` | AC54, AC64, AC103 rewritten; AC107–AC110 added |
| `CarTV/Tests/CarPlayTemplateTests.swift` | AC104–AC106 added |
| `docs/SPEC.md` | the eighth pass; AC104–AC110 |
| `AGENTS.md` | the eighth pass's gotchas |
| `CHANGELOG.md` | the fixes |
| `docs/review-2026-11-03.md` | §1.17, §2, §3, §3a, §5 |

## Verification

* `xcodebuild -sdk iphoneos -destination 'generic/platform=iOS' CARPLAY_CATEGORY=video build` → **BUILD SUCCEEDED**
* `scripts/device_test.sh` on the **physical iPhone 13**
  (`00008110-001C60423CB8401E`) → **`Executed 132 tests, with 8 tests skipped
  and 0 failures (0 unexpected) in 34.910 seconds`** → `** TEST SUCCEEDED **`
* the eight skips are the repository contract tests, which read a file of the
  checkout that does not exist on the phone (`RepositoryFixture.skipUnlessPresent()`)
* the SPEC ↔ test trace is exact: **110 ACs ↔ 110 test names**
* the **iPhone 18 Pro simulator was not touched**: not booted, not installed
  to, not installed from. Every build used `generic/platform=iOS`.

## Still needs a human

* **The picture on a real car's screen.** The hand-off is the fix for the
  black display, and the device log is what proves it: the route has to be
  evaluated with the car's endpoint selected (`Local Playback = 0` and the
  endpoint "CarPlay (ScreenMain)"), and `isExternalPlaybackActive` has to
  become true. On the phone the switch must then say **"Car connected"**, the
  phone's picture must go away **at that moment**, and **"Play on Phone"**
  must bring it back — and it must stay on the phone.
* **The one tap that matters**: opening DrivePlay from the car's app list.
  That is what proved the crash, so it is what proves the fix.
