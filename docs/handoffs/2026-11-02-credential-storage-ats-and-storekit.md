# Handoff — 2026-11-02 — credential storage, transport security, screen capture, purchases

> Continued in
> [2026-11-02-carplay-entitlement-testing-and-pro-flow.md](2026-11-02-carplay-entitlement-testing-and-pro-flow.md)
> — the open items below (the CarPlay attach, the video entitlement, the public-IP
> `http://` provider) are closed there.

## What was asked

"i am back lets finish today" — close the four code items that were still open
after the 2026-10-31 review:

1. the screen capture was never stopped (ReplayKit),
2. `http://` everywhere plus `NSAllowsArbitraryLoads: true` (App Transport Security),
3. plaintext credentials in `UserDefaults` / `Documents` (Keychain),
4. `StoreKitManager` with a hardcoded `isProUnlocked = true` (StoreKit 2).

## What was done

| # | Item | State |
|---|---|---|
| 1 | ReplayKit lifecycle | **Done** |
| 2 | ATS / URL policy | **Done** |
| 3 | Credentials in the Keychain | **Done** |
| 4 | StoreKit 2 | **Done** (the purchase layer is real; the product id and the paywall placement are still a product decision) |

### 1. Screen capture outlived the external display

`stopMirroring()` had **no callers**: the capture was only stopped by the Cast
tab's close button. A tab switch or the external display going away left the
recording running — the recording indicator stayed on and the battery drained.
The capture handler also drove `AVSampleBufferDisplayLayer` from ReplayKit's
queue, which is not thread-safe.

One stop path now serves all three callers (close button, tab switch, scene
teardown), and the renderer is only touched on the main thread.

### 2. App Transport Security allowed plain HTTP to every host

`NSAllowsArbitraryLoads: true` was set app-wide, so any address could be
fetched over an unencrypted connection. Now:

- `NSAllowsLocalNetworking: true` — plain HTTP still works for a server on the
  LAN (the common case for a Jellyfin/Xtream box at home),
- `NSAllowsArbitraryLoadsInWebContent: true` — the in-app browser tab keeps
  working,
- every server URL the app builds goes through one policy (`URLPolicy`), so the
  code and ATS agree: `http` for local hosts, `https` for everything else.

**Trade-off:** a provider that serves a *public* IP over plain `http://` is now
blocked by ATS. The revert is one key in `project.yml`
(`NSAllowsArbitraryLoadsInWebContent` → `NSAllowsArbitraryLoads`).

### 3. The credentials were readable from the app's own files

Three leaks, all from the same root cause (a secret written to a file that
everybody can read):

- `PlaylistStore.saveSources()` JSON-encoded `PlaylistSource` — with its
  `username`, `password` and `serverToken` — into `UserDefaults`.
- The Xtream stream URLs carry the credentials in the path
  (`/live/<user>/<pass>/<id>.m3u8`) and were written to
  `Documents/saved_channels.json`.
- The Jellyfin stream URLs carry the access token in the query
  (`?api_key=<token>`), and the watch history kept the same URLs in
  `UserDefaults`.

The fix keeps the same shape for every writer and reader:

- `CredentialStore` (Security framework) holds one `SourceCredentials` item per
  source, keyed by the source id, `kSecAttrAccessibleAfterFirstUnlock`.
- `PlaylistSource` has a custom `Codable`: it never *encodes* the secrets and
  still *decodes* them, so a source saved by an older build is migrated into the
  Keychain the first time it is read.
- `CredentialRedactor` takes the secrets out of a URL (user info, path segment,
  query value) before it is written and puts them back when it is read. The
  copies on disk hold placeholders; the copies in memory hold the real thing.
- `removeSource` deletes the Keychain item; the Plex sign-in now goes through
  `PlaylistStore.addSource(_:)`, so it is saved at all (it was appended straight
  to the array before and lost on the next start).

If the Keychain refuses a write (an unsigned build has no keychain access), the
source keeps its secrets in the plist and the app logs it. Losing the password
would mean typing it again after every restart, which is worse than the old
behaviour — and it only happens in a build that cannot use the Keychain at all.

### 4. The purchase layer

`StoreKitManager` was a stub: `isProUnlocked = true`, an empty `products`
array, and an empty `updatePurchasedProducts()`. It now loads the products,
buys, restores, listens to `Transaction.updates` and reads
`Transaction.currentEntitlements`. Nothing in the app is gated behind Pro (that
is still the product decision), so the app behaves exactly as before.

## Verification

```
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES test
→ Executed 46 tests, with 0 failures  ** TEST SUCCEEDED **
```

The app was rebuilt, installed on the booted simulator (`iPhone 18 Pro`) and
launches; the home screen renders with `GPS SAT-LOCK: ACTIVE`.

**The Simulator build has to be signed.** An unsigned app has no
`application-identifier`, so the Keychain refuses every write with `-34018`
(`errSecMissingEntitlement`) — the credentials of a source cannot be stored at
all. Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) is enough; a device build is
signed with the developer identity as usual. `AGENTS.md` carries the rule.

## Open items (need the user, a device, or Apple)

1. **CarPlay attach.** The CarPlay Simulator app is installed and running; the
   attach is a one-click Device Hub action (run the app → Device Hub → the
   attached peripheral "CarPlay Simulator"). Until then the templates are
   type-checked but not seen on a car screen.
2. **The CarPlay video entitlement.** `CarTV.entitlements` grants
   `com.apple.developer.carplay-audio` only. Video needs the
   `com.apple.developer.carplay` capability, which Apple grants per-app.
   **Ask first** — it is a capability change and the device build stops signing
   until Apple grants it.
3. **A public-IP `http://` provider** is now blocked by ATS (see the
   trade-off above) — one key in `project.yml` if the provider needs it.
4. **A playlist with credentials in the URL itself** (an M3U entry like
   `http://user:pass@host/stream.ts`) keeps them in the channel file: the
   redactor only knows the credentials of the *source*. The source's own
   credentials — the ones the app asks for — are all in the Keychain now.

## Files changed

```
CHANGELOG.md                                     (ReplayKit, ATS, credentials, tests 35 → 46)
AGENTS.md                                        (the Simulator build has to be signed)
docs/SPEC.md                                     (new: the milestone spec, AC → test table)
docs/handoffs/2026-10-31-…                       (open items 2–5 closed, test count updated)
docs/handoffs/2026-11-02-…                       (new: this file)
CarTV/Sources/Services/CredentialStore.swift     (new: Keychain store + URL redactor)
CarTV/Sources/Models/PlaylistSource.swift        (custom Codable: no secrets in the plist)
CarTV/Sources/Services/PlaylistStore.swift       (Keychain save/load/migrate/delete, redaction, addSource)
CarTV/Sources/Services/WatchHistoryStore.swift   (redacted URLs at rest, restored on load)
CarTV/Sources/Services/StoreKitManager.swift     (StoreKit 2)
CarTV/Sources/Views/Settings/ProPaywallView.swift (buy + restore, when the product exists)
CarTV/Sources/Views/Settings/AddSourceSheet.swift (Plex sign-in is saved now)
CarTV/Sources/App/CarTVApp.swift                 (loads the products at launch)
CarTV/Sources/App/ExternalDisplaySceneDelegate.swift (stops the capture on disconnect)
CarTV/Sources/Views/CarPlayVideoViewController.swift (one stop path, main-thread renderer)
CarTV/Sources/Services/URLPolicy.swift           (new: http for local hosts, https otherwise)
CarTV/Sources/Parsers/XtreamParser.swift         (shares the credential encoder)
CarTV/Sources/Services/JellyfinClient.swift      (uses URLPolicy)
CarTV/Tests/CredentialStorageTests.swift         (new, 5 tests: AC19–AC23)
CarTV/Tests/StoreKitTests.swift                  (new, 1 test: AC24)
CarTV/Tests/ScreenCaptureLifecycleTests.swift    (new, 2 tests: AC14–AC15)
CarTV/Tests/URLPolicyTests.swift                 (new, 3 tests: AC16–AC18)
project.yml                                      (ATS, GENERATE_INFOPLIST_FILE for the test bundle)
CarTV.xcodeproj/project.pbxproj                  (regenerated by xcodegen)
```
