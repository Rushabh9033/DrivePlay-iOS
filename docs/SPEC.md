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

**Every acceptance criterion below has exactly one test.** The test name
carries the criterion number (`test_AC<n>_…`), so the trace is mechanical.

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
| 54 | The car takes the picture — the phone stops drawing it and the output follows | `PlaybackManagerTests` |
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

- Making CarPlay show **video**: the scene is template-only, and the video
  capability has to be granted by Apple (`com.apple.developer.carplay-video`).
  The request is prepared in `docs/carplay-video-request.md`; it has to be sent
  from the Apple account that owns the team, because it includes the CarPlay
  Entitlement Addendum. The chain behind it — capture, encode, serve, play — is
  finished and tested (AC29–AC32); what the grant adds is the car's video
  surface.
- Putting anything behind the Pro upgrade: the app ships with every feature
  unlocked. The purchase layer is in place, the product id and the paywall
  placement are still a product decision.
