# Handoff — the minimised player, the microphone crash and the portrait video (2026-11-04)

## The request

> *"i want to add a features of played video should be show below like youtube has minimise but not floating window i will show u image"*

> *"app crashing when i use mic feature where mic feature is working but app crash i don't know form mobile side issue or u additing the code so it can be happens and another issue is that my iphone ahs a locale video that steam in to the portrait mode but in the drive tv i got black parts on both side means it render portrait video in landscape layout so fix that u got the issue what i am talking about and before complete previous task then impoment int his taask and the minimise bar should be not cover the main tab bar it saty uper side of the tab bar like u can see in the image"*

> *"also i can minimize by swipe down like youtube has feature also suggeste me more this kind of features make ap more good"*

Four things: the **bar** (YouTube's minimised player, docked above the tab bar
— not a floating window), the **swipe down**, the **voice search crash** and
the **portrait video's black bars**.

## 1. The bar was never on the screen

The feature was first built the obvious way — a `safeAreaInset(edge: .bottom)`
on the `TabView` — and it **never rendered**.

**The evidence.** A probe dumped the live view hierarchy of the running app:
the root `_UIHostingView<MainTabView>` had **exactly one** subview, the
platform view host. Nothing else. The state was right (`presentationMode ==
.mini`, `currentChannel` set), the bar was simply not there.

**The cause.** On iOS 26+ the `TabView` is **UIKit's own**
(`UIKitAdaptableTabView`), and it swallows the bottom inset's content whole.
It is not a SwiftUI `TabView` any more, and the inset it does not lay out is
the inset the app writes into.

**The fix.** The bar is an **overlay** in the `ZStack` — the same shape the
docked player already proved works — and the space it leaves is the tab bar's
height **measured from the live window**:

```swift
static func tabBarHeightInWindow() -> CGFloat {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let phone = scenes.filter { $0.session.role == .windowApplication }.flatMap(\.windows)
    let window = phone.first { $0.isKeyWindow } ?? phone.first
        ?? scenes.flatMap(\.windows).first
    guard let window else { return 0 }
    return firstTabBar(in: window)?.bounds.height ?? 0
}
```

**Why the measurement and not a constant.** On iOS 26+ the tab bar is a
`_UIBottomTabBarGroupView` (83 pt on this iPhone 13) with a **floating pill**
inside it (`_UITabBarItemPlatterView`, 62 pt), and the home indicator's safe
area is *below* the pill. A hardcoded 49 (the old tab bar) or 34 (the safe
area) puts the bar either behind the pill or in the middle of the gap. The
measurement is taken again whenever the bar appears, because the tab bar is
certainly in the window by then.

**The bar.** `MiniPlayerBar` — the channel's picture (`AsyncImage` of the
channel's logo, a `tv` glyph when there is none), the channel's name, ▶/⏸, ⏭
and ✕. The ⏭ plays the **next channel of the group the current one belongs
to** (`PlaylistStore.channels(inGroupOf:)`) — the order the grid plays in — and
the ✕ closes the video.

## 2. The swipe down

`MiniPlayerSwipe.shouldMinimize(translation:)` is the one rule, and it is
**testable**: the drag has to go **down** and further down than sideways, so a
sideways scroll never dismisses the player. Both surfaces use it — the docked
player's picture (`DragGesture`) and the full-screen player
(`UISwipeGestureRecognizer(.down)` on `LandscapeAVPlayerViewController`).

## 3. The voice search crashed the app

*"the mic feature is working but app crash."* The microphone worked — the
transcript arrived — and the app died with it.

**The cause.** `SFSpeechRecognizer` calls its result handler on **its own
queue**. The handler published `recognizedText`, closed the search sheet and
started the player **from that queue** — *"Publishing changes from background
threads are not allowed"*. That is a **fatal error, not a signal**, so there is
**no crash report**; that is why the crash logs had nothing to show.

**The fix.** A `nonisolated` seam that crosses to the main actor before
anything touches the app's state:

```swift
nonisolated func handleTranscript(_ transcript: String?,
                                  isFinal: Bool,
                                  error: Error?,
                                  onResult: @escaping @MainActor (String) -> Void) {
    Task { @MainActor [weak self] in
        guard let self = self else { return }
        if let transcript {
            self.recognizedText = transcript
            onResult(transcript)
        }
        if error != nil || isFinal { self.stopRecording() }
    }
}
```

## 4. The portrait video's black bars

*"in the drive tv i got black parts on both side means it render portrait video
in landscape layout."* Every surface asked the player to **fit** the picture
(`.resizeAspect`), so a 9:16 phone-shot video stood in the middle of the
landscape car's screen with a black bar on each side.

`VideoGravityPolicy.gravity(for:)` reads the item's own `presentationSize` —
the size **with** the preferred transform, so a rotated video is measured the
way it is shown — and fills the frame only when the picture is taller than it
is wide. A **landscape** channel keeps `.resizeAspect`, because a logo at the
edge of the picture must not be cropped away.

The policy is applied in every place that draws the video: `PlayerUIView`
(the docked and in-app surfaces), `LandscapeAVPlayerViewController` (the
full-screen one) and `InCarAutomotiveController` (the car's own screen).

## The checks

| AC | What it proves | Test |
|----|----------------|------|
| 112 | The bar carries the channel's picture and its name | `MiniPlayerTests` |
| 113 | The bar sits **above** the tab bar and never covers it | `MiniPlayerTests` |
| 114 | The bar plays and pauses the video, and ✕ closes it | `MiniPlayerTests` |
| 115 | ⏭ plays the next channel of the current one's group | `MiniPlayerTests` |
| 116 | A swipe **down** puts the player away, a drag to the side does not | `MiniPlayerTests` |
| 117 | The transcript arrives on the main actor | `VoiceSearchTests` |
| 118 | A portrait video fills the frame, a landscape one is fitted | `VideoGravityTests` |

## Files touched

| File | What changed |
|------|--------------|
| `CarTV/Sources/Views/Player/MiniPlayerBar.swift` | **new** — the bar, and the swipe rule |
| `CarTV/Sources/Views/MainTabView.swift` | the bar as an overlay, the measured tab bar height |
| `CarTV/Sources/Views/Player/VideoPlayerView.swift` | `VideoGravityPolicy`, the gravity in the player views, the full-screen swipe down |
| `CarTV/Sources/Views/Player/DockedPlayerContainerView.swift` | the swipe down on the picture |
| `CarTV/Sources/Services/VoiceSearchManager.swift` | the main-actor hop for the transcript |
| `CarTV/Sources/Services/PlaybackManager.swift` | `.mini`, `showsMiniPlayer`, `minimizeToMiniBar()`, `expandFromMiniBar()`, `playNextChannel(in:)` |
| `CarTV/Sources/Services/PlaylistStore.swift` | `channels(inGroupOf:)` — the group's own order |
| `CarTV/Sources/Views/CarPlayVideoViewController+Actions.swift`, `+Video.swift` | the gravity on the car's screen |
| `CarTV/Tests/MiniPlayerTests.swift`, `VideoGravityTests.swift`, `VoiceSearchTests.swift` | **new** AC116–AC118, AC117 |
| `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md` | this pass |

## Gotchas learned

- **The iOS 26+ `TabView` swallows `safeAreaInset(edge: .bottom)` whole.** The
  root `_UIHostingView<MainTabView>` ends up with one subview. A bar that has to
  sit above the tab bar is an **overlay**, not an inset.
- **The tab bar's height is not a constant on iOS 26+.** It is a group view
  with a floating pill inside it; measure it from the live window.
- **`SFSpeechRecognizer` calls back on its own queue.** Publishing from there
  is a fatal error — and a fatal error writes **no crash report**.
- **A portrait video needs `.resizeAspectFill`; a landscape one must not have
  it.** Measure the item's `presentationSize` — the size **with** the
  preferred transform.

## Still needs a human

* The bar on the phone's screen: that the picture leaves the phone's screen
  when the bar is up, that the bar is **above** the pill and not on it, and
  that a swipe down on the docked player leaves the bar behind.
* The voice search, **spoken to** — the test proves the transcript arrives on
  the main actor, not that a name is understood.
* A portrait video on the **car's** screen, side by side with a landscape one.
