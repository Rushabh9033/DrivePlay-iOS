# SPEC — DrivePlay hardening milestone

The app has to work the same on the iOS Simulator and on a real iPhone, and it
must not keep the user's server credentials in a file anybody can read.

This milestone covers the bugs found in the full-codebase review of
2026-10-31 → 2026-11-02: the parsers, the car shelves, the screen capture, the
transport security policy, the credential storage and the purchase layer.

It also covers the **screen-share chain** — the phone's screen on the car's
display, WhatsApp-video-call style:

    ReplayKit capture → H.264 fragments → a local HTTP server → the app's AVPlayer

A car screen never shows a mirror, only the video the app plays. So the app
records its screen, serves it as a live HLS stream and plays that very stream;
the car draws it in the now-playing area. The same playlist is served on the
local network, so a head unit that is not CarPlay can watch it too.

The **second review** (2026-11-03, AC70–AC89) covers what that first round
missed: the parsers that read a container's title as an item's title, the
libraries that were cut short or emptied by one bad entry, the servers that
answered with the first page only, the Plex source that pointed at the cloud
instead of the account's own server, the picker that moved a checkmark instead
of a track, the car rows that did nothing, and the phone that never learned
that it had been turned.

The **third pass** (2026-11-03, AC90–AC91) covers what the **device** found:
the artwork URL carried the account's token into the library file and into the
watch history in the clear, and the watch history's own copy of the URL was
the redacted one — so "watch again" played a URL with a placeholder in it.

The **fourth pass** (2026-11-03) has no new criteria of its own: it fixes the
one that was already there but never ran. **AC67** skipped itself whenever the
microphone permission was missing, so the suite reported *"0 failures"* while
the voice search died on the phone with *"com.apple.coreaudio.avfaudio error
1852797029"*. The cause was a race: `setActive(false)` returns before the
session has really gone, so the switch to the recording category landed on a
session that was still active, and the route to the microphone — which iOS
builds in the background — was not there yet when the recorder started. The
recorder now waits for the route.

**Every acceptance criterion below has exactly one test.** The test name
carries the criterion number (`test_AC<n>_…`), so the trace is mechanical.

The **fifth pass** (2026-11-03, the device) covers what the device found and the
Simulator could not: the encoder refused every frame the app's own code produced
(*"FigSampleBufferSerialization err=-19642"*), because the buffer was not
**IOSurface-backed** — so the screen share never produced a fragment on a real
phone, while the Simulator's encoder took it without complaint. And the car's
cards carried a tint of ours, which painted a green frame around every card of
every category (AC97).

The **sixth pass** (2026-11-03) is the picture on the car's display and the
car's own browser. The picture was **offered** to the car, never **handed
over**: the system only looks at the AirPlay route when the picture is offered,
and the car's video endpoint only exists once the CarPlay scene is up — so the
offer that happened before that found no endpoint at all (the system's own log
said *"Local Playback = 1"*) and the car's display stayed black (AC98). The
route itself cannot be chosen by an app — there is no public API for it — so
"Play on Car Display" now hands the picture over **at once** when a car is
connected, and the system's list of displays is only the fallback for a phone
that has no car. The Browser tab was a list of sites that did nothing; it is
now a **list** whose first row opens the **address bar** — a search template,
pushed onto the stack — and what the user types goes to the phone's own
browser, which applies the rule the phone always applied: a URL is a URL,
anything else is a search (AC99, AC100).

The **seventh pass** (2026-11-03) is what the car found: the Browser tab had
been made a **search template**, and the tab bar **rejects** one — it raises
an `NSException` and the app dies with a SIGABRT at **every** CarPlay connect
(AC102). The Browser tab is a list and the address bar is **pushed**; the
address bar's own row list is the way into it (AC101). And a video the user
starts on the phone now goes to the car's display **by itself** when a car is
connected — the phone keeps no picture and the car shows the video (AC103).

The **eighth pass** (2026-11-03) is the picture's **home** and the car's
screen's **speed**. The hand-off hid the phone's picture straight away, so a
car whose video endpoint was not ready yet left the video on **neither**
screen — the user's *"sometimes only in the car, sometimes only on the phone"*.
Now the picture belongs to the **system's** answer: the phone keeps drawing it
until the system reports the picture on the car, takes it back when the user
asks, and the ladder that offers the picture again stops the moment the user
takes it back (AC107, AC108). The banner and the picture can no longer
disagree — the system is the only writer of the flag.

The car's screen was slow for three separate reasons, all measured: the
pictures of **different** servers waited for each other (one global gap held
the whole screen back — 18 ms for eight servers now, against 1.6 s before,
AC105); the car was told about **every** picture separately and reloaded the
whole row each time (once per batch now, AC106); and the now-playing artwork
was **drawn** four times a second while a video played — a 512×512 gradient on
the main thread, four times a second, which is what made the phone stutter
(AC109). A video that has just started is not offered to the car a second
time, because the item was attached with the route already open (AC110).

## Acceptance criteria

| AC | Criterion | Test |
|----|-----------|------|
| 1 | The M3U parser reads the name, group, artwork and resolution of an entry from its own tags only — no inheritance from the previous entry, no truncation at a comma | `SourceParserTests`, `M3UParserTests` |
| 2 | The car's Home tab shows an empty state when there is nothing to show | `CarPlayTemplateTests` |
| 3 | Empty groups are not listed in the car's Home tab | `CarPlayTemplateTests` |
| 4 | The car channel picker is a list of channel rows | `CarPlayTemplateTests` |
| 5 | Every car channel row requests the video presentation | `CarPlayTemplateTests` |
| 6 | The handset search box does not shrink the car catalogue | `InCarShelfTests` |
| 7 | The Plex pin response is decoded as Plex actually sends it | `SourceParserTests` |
| 8 | An authenticated Plex pin is decoded | `SourceParserTests` |
| 9 | Importing the same file name twice keeps both files | `LocalMediaServiceTests` |
| 10 | The offline vault index is written atomically and reloads | `LocalMediaServiceTests` |
| 11 | The install script has no hardcoded device and a bounded wait | `InstallScriptTests` |
| 12 | The car shelves are only rebuilt when the channels or the favourites change | `InCarShelfTests` |
| 13 | A favourite change does rebuild the shelves | `InCarShelfTests` |
| 14 | Disconnecting the external display stops the screen capture | `ScreenCaptureLifecycleTests` |
| 15 | Stopping the mirror clears the active flag | `ScreenCaptureLifecycleTests` |
| 16 | Plain HTTP is only used for local hosts, HTTPS for everything else | `URLPolicyTests` |
| 17 | A server address without a scheme gets one, and the trailing slash goes | `URLPolicyTests` |
| 18 | The host is read out of an address with a scheme, a port or a path | `URLPolicyTests` |
| 19 | Encoding a source leaves the secrets out | `CredentialStorageTests` |
| 20 | A source saved by an older build still decodes its secrets, so they can be migrated | `CredentialStorageTests` |
| 21 | The Keychain keeps the secrets and hands them back | `CredentialStorageTests` |
| 22 | A stream URL loses its secrets on disk and gets them back for playback | `CredentialStorageTests` |
| 23 | Saving the sources keeps the secrets out of `UserDefaults` | `CredentialStorageTests` |
| 24 | Only the Pro product unlocks Pro | `StoreKitTests` |
| 25 | A request blocked by App Transport Security says what to do about it | `URLPolicyTests` |
| 26 | The local StoreKit configuration offers the Pro product the app looks for | `StoreKitConfigurationTests` |
| 27 | The entitlements files ask for exactly what the app id carries — the audio build asks for audio, the video build for audio **and** video | `CarPlayEntitlementTests` |
| 28 | The entitlement helper follows the entitlements file and finds the phone at run time | `CarPlayEntitlementTests` |
| 29 | The screen share serves a live HLS stream over HTTP, and only to a caller that has the token | `ScreenShareTests` |
| 30 | The share says so when the screen cannot be recorded | `ScreenShareTests` |
| 31 | The demo picture travels the same encoder and server as a real share | `ScreenShareTests` |
| 32 | The player's video output plays the stream the app serves — the picture advances | `ScreenShareTests` |
| 33 | The screen-share row of the car's Cast tab asks CarPlay for the video surface | `CarPlayTemplateTests` |
| 34 | A capture that delivers no frame hands over to the demo picture instead of dying | `ScreenShareTests` |
| 35 | The build picks the entitlements file and tells the app which CarPlay category it has | `CarPlayEntitlementTests` |
| 36 | The app asks for the video surface exactly when the build carries the video entitlement | `CarPlayTemplateTests` |
| 37 | The broadcast extension can tell the app where its stream is | `ScreenShareTests` |
| 38 | The app takes the address the broadcast extension announces | `ScreenShareTests` |
| 39 | The relay waits for a broadcast without wedging the share | `ScreenShareTests` |
| 40 | The announcement of the broadcast extension starts the share | `ScreenShareTests` |
| 41 | The car's screen-share row starts the demo picture on the Simulator, and waits for the broadcast on a device | `ScreenShareTests` |
| 42 | The encoder can be closed when it never received a frame | `ScreenShareTests` |
| 43 | The relay listens for a broadcast without disturbing a share that is already running | `ScreenShareTests` |
| 44 | The broadcast picker points at the app's own extension | `ScreenShareTests` |
| 45 | A failed CarPlay template call is reported, never thrown — tapping a row on the car cannot kill the app | `CarPlayPresentationTests` |
| 46 | An announcement that arrives in pieces is still taken — a split line is half an address, not a bad one | `ScreenShareTests` |
| 47 | A relay that cannot listen says so, instead of waiting for an announcement that can never come | `ScreenShareTests` |
| 48 | The playlist is served correctly while the fragments are written — the window is filled and read under one lock | `ScreenShareTests` |
| 49 | The player offers the video to the car's display — a CarPlay video app has to support AirPlay video streaming | `PlaybackManagerTests` |
| 50 | The app may keep running in the background while the screen is being captured | `ScreenShareTests` |
| 51 | The picture can be brought back from the car to the phone | `PlaybackManagerTests` |
| 52 | The player keeps a video output while the phone shows no picture | `PlaybackManagerTests` |
| 53 | The picture keeps playing when the phone is minimised or locked | `PlaybackManagerTests` |
| 54 | The car takes the picture — the phone stops drawing it when the **system** says the car has it, and the output follows | `PlaybackManagerTests` |
| 55 | The car's screen is a tab bar with the tabs Home, Favorites, Cast and Browser, each with its own title and icon | `CarPlayTabTests` |
| 56 | The Home tab shows the whole playlist under "All", with the count it really has | `CarPlayTabTests` |
| 57 | Every category shows its own title, the count it really has and its own artwork | `CarPlayTabTests` |
| 58 | Every category has a way into all of its entries | `CarPlayTabTests` |
| 59 | The Favorites tab shows the favourites the phone holds | `CarPlayTabTests` |
| 60 | The Cast tab shows where the picture is and what the share does | `CarPlayTabTests` |
| 61 | The Browser tab offers the sites of the app's own browser and opens them on the phone | `CarPlayTabTests` |
| 62 | A logo is drawn at its own aspect ratio — never stretched, never clipped | `CarPlayArtworkTests` |
| 63 | A logo is fetched once, however often the screen is rebuilt | `CarPlayArtworkTests` |
| 64 | The picture can go back to the car after it came back to the phone | `PlaybackManagerTests` |
| 65 | The artwork is drawn at the car's display scale, not the phone's | `CarPlayArtworkTests` |
| 66 | A rebuilt screen does not draw the cards again | `CarPlayArtworkTests` |
| 67 | The voice search can take the microphone from the player | `VoiceSearchTests` |
| 68 | The player's audio session comes back when the voice search ends | `VoiceSearchTests` |
| 69 | A search result picked on the car plays the channel it stands for | `CarPlaySearchTests` |
| 70 | The DLNA parser does not take the title of the container for the title of the first item | `ReviewRegressionTests` |
| 71 | The DLNA parser takes the first `<res>` of an item — the others are not concatenated into it | `ReviewRegressionTests` |
| 72 | The M3U parser reads an attribute whose value is not quoted | `ReviewRegressionTests` |
| 73 | The M3U parser does not relabel a channel that says "HD" | `ReviewRegressionTests` |
| 74 | The library survives one entry that cannot be read | `ReviewRegressionTests` |
| 75 | The old library is not thrown away while it cannot be read | `ReviewRegressionTests` |
| 76 | The Jellyfin library is read page by page — it is not cut off after the first page | `ReviewRegressionTests` |
| 77 | The Jellyfin artwork carries the token — the image loader cannot send a header | `ReviewRegressionTests` |
| 78 | A Plex source points at the account's own media server, not at plex.tv | `ReviewRegressionTests` |
| 79 | Only the player changes the track; a track that is not there is not selected | `ReviewRegressionTests` |
| 80 | The Cast tab has no dead picture rows while there is no player | `ReviewRegressionTests` |
| 81 | The "stop mirroring" row exists only while there is a share to stop | `ReviewRegressionTests` |
| 82 | The channel picker pages, so every channel of a category is reachable | `ReviewRegressionTests` |
| 83 | The Home tab stays inside CarPlay's item budget | `ReviewRegressionTests` |
| 84 | An announcement that never ends is dropped instead of growing the buffer without end | `ReviewRegressionTests` |
| 85 | The device generates its orientation notifications — the rotate handler can run at all | `ReviewRegressionTests` |
| 86 | A copy that cannot happen creates no vault entry | `ReviewRegressionTests` |
| 87 | The temporary copy of an import is removed — the vault keeps the only copy | `ReviewRegressionTests` |
| 88 | The extractor can be used again after a result | `ReviewRegressionTests` |
| 89 | A search query with spaces around it still matches | `ReviewRegressionTests` |
| 90 | The artwork loses its token on disk and gets it back — the image loader cannot send a header, so the token rides in the query | `CredentialStorageTests` |
| 91 | The watch history plays the real URL, not the placeholder | `CredentialStorageTests` |
| 92 | The categories the Home tab has no room for are still on the car, through "All categories" | `CarPlayTabTests` |
| 93 | The category list shows every category with the count it really has, and opens its channels | `CarPlayTabTests` |
| 94 | A logo that arrives patches the card that shows it — the screen is not rebuilt | `CarPlayTabTests` |
| 95 | The card that shows a logo is drawn from that logo, not from a lookup in a cache that may have thrown it away | `CarPlayArtworkTests` |
| 96 | A logo the server refuses is asked for again | `CarPlayArtworkTests` |
| 97 | The car's cards carry no colour of our own — the car paints the card, the artwork carries the logo | `CarPlayArtworkTests` |
| 98 | With a car connected, "Play on Car Display" hands the picture over at once — the system's list of displays is never shown | `CarOutputSwitchTests` |
| 99 | The Browser tab's header is a search bar, and what is typed goes to the phone's own browser — a URL is a URL, anything else is a search | `CarPlayTabTests` |
| 100 | A site of the browser opens on the phone — the car has no web view of its own | `CarPlayTabTests` |
| 101 | The Browser tab is a **list** — the way into the address bar, the page the phone shows now, and the app's own sites | `CarPlayTemplateTests` |
| 102 | The tab bar is built from **lists** only — the tab bar rejects a search template and takes the app down with it | `CarPlayTemplateTests` |
| 103 | A video started on the phone goes to the car's display at once when a car is connected | `PlaybackManagerTests` |
| 104 | The car's Home tab is built in a moment — the car waits that long for a screen | `CarPlayResponsivenessTests` |
| 105 | The pictures of **different** servers arrive together — one server's quota does not hold up the others | `CarPlayResponsivenessTests` |
| 106 | The car is told **once** for a batch of pictures, not once per picture | `CarPlayResponsivenessTests` |
| 107 | The picture is never on neither screen — the phone keeps it until the system says the car has it | `PlaybackManagerTests` |
| 108 | The picture the user took back does not jump back to the car | `PlaybackManagerTests` |
| 109 | The now-playing artwork is drawn once per channel, not four times a second | `PlaybackManagerTests` |
| 110 | A video that has just started is not offered to the car twice | `PlaybackManagerTests` |

## Verification

```bash
# The Simulator build has to be signed (ad-hoc is enough): an unsigned app has
# no application-identifier, so the Keychain refuses every write (-34018).
scripts/run_tests.sh

# The same thing, spelled out:
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES test

# On the **phone** — the CarPlay video surface and the broadcast can only be
# exercised there, and Xcode 27's CarPlay Simulator hosts physical devices
# only:
scripts/device_test.sh
```

The project is generated from `project.yml` — run `xcodegen generate` after
changing it.

## Non-goals of this milestone

- **Choosing** the car's display from the app: the car's display is an AirPlay
  destination and no public API picks that route — only the system's list of
  displays does. The app therefore offers the picture to the car (the video
  capability is granted, and the car draws the picture in its own now-playing
  area), and falls back to the system's list only when no car is connected.
- Drawing a **web page** on the car's screen: CarPlay has no web view, and
  Apple does not allow one. The car's Browser tab is a search bar; the page it
  opens runs in the app's own browser on the phone, and reaches the car through
  the phone's screen share.
- Putting anything behind the Pro upgrade: the app ships with every feature
  unlocked. The purchase layer is in place, the product id and the paywall
  placement are still a product decision.
