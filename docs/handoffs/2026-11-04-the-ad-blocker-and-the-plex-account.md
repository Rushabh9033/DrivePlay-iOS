# Handoff — the ad blocker and the Plex account (2026-11-04)

## The requests

> *"the ad blocker is also blocking captcha of the sonyLIV login (find issue and tell me the truth) FIx that"*

> *"on chrome side the status show succesfull but on the mobile side it show me 'No Plex media server found on this account' so fix"*

> *"sonyliv captach block inside our mobile app browser not the actual browser of my mac"*

## 1. The truth about the captcha

**No rule ever matched the reCAPTCHA addresses.** Checked against the exact
rules that were on the phone: `enterprise.js`, `api2/anchor`, `api2/bframe`
and `gstatic` were **allowed** by all 237 host patterns, and no pattern in the
list contains the word *"captcha"*. A real `WKWebView` on Google's reCAPTCHA
demo page, with the app's compiled rules applied, still had `window.grecaptcha`
as an **object** — the same as the run without them.

So the captcha was not blocked. The **page** was broken by four other things,
and every one of them was real:

1. **A rule matched the whole URL — the query string included.**
   `url-filter` is a regex searched *anywhere* in the URL, so the rule for
   `googletagmanager.com` also stopped
   `https://www.google.com/ccm/collect?…&scrsrc=www.googletagmanager.com` —
   **Google's own collector**, killed by a host it only *mentioned*. The rules
   took **33 of the SonyLIV sign-in page's 93 resources** that way. The rules
   now match the **host** of a request (`if-domain`) and nothing else. (AC121)
2. **The rule that hides the ad boxes ran on every frame.**
   A captcha badge, a payment form and a consent banner all live in a
   **third-party frame**. The rule is now `load-type: ["top-frame"]` only, and
   it excepts the captcha and identity providers with `unless-domain`. (AC122)
3. **There was no way out.** `isEnabled` existed and was **never read** — the
   "Ad Shield" sheet was a read-only notice. It is a real control now: a
   master switch and a **per-site switch** (an `ignore-previous-rules` rule
   that comes **last**, so it wins). (AC123–AC125)
4. **The tag manager was blocked.** `googletagmanager.com` is not an ad host —
   it is the pipe a site's **own** configuration travels through, and
   SonyLIV's sign-in page took its login-and-tray setup from there. It is not
   blocked any more; the ad hosts it fires at (DoubleClick, Google Ads, Google
   Analytics) are blocked on their own. (AC126)

A fifth thing was found on the way: **the compiled rule list is cached under
its identifier.** WebKit keeps it and the app asks for it *by name* before it
compiles anything, so a list compiled from the **old** rules was found and
used and the new rules were **never even compiled**. The identifier is now
`DrivePlayAdBlockerRulesV7`.

And a sixth: **the rules apply to the *next* load, and they are compiled in
the background.** The browser reloaded the page the moment the switch was
flipped — with the *old* rules — and the switch looked like it had done
nothing. The pages are now loaded again **after** the compile, by the one
place that knows the rules changed (`AdBlockerEngine.applyToAllOpenTabs()`).

### The captcha itself is a feature flag

Read out of SonyLIV's own bundle: the sign-in page decides on
`config.resultObj.config.enableReCAPTCHA` (it is `false` in the page's
preloaded state today, and `true` for the accounts SonyLIV has switched over).
When the flag is on the page injects
`<script id="reCaptchaScript" src="https://www.google.com/recaptcha/enterprise.js?render=…">`
**itself** and calls `grecaptcha.enterprise.execute(…)`. Its own code is
`try { grecaptcha && … }`, so a `grecaptcha` that is missing is swallowed and
the OTP request goes out **without** the token — as `API_VERSION_4_0`, and the
server refuses the login. **That** is the shape of the failure the user saw:
not an error, a login that simply does not happen.

### What the app now does

`AdBlockerEngine.apply(to:)` is the one place the rules go into a web view,
and `ruleListToApply` is the decision the tests read. The "Ad Shield" sheet
has a master switch and a **per-site** switch, and the site's key is its host
without the `www.` (`AdBlockerEngine.siteKey(for:)`).

## 2. The Plex account that had no server

The account was linked in Chrome ("Account Linked", signed in as
`rushabhmavani493`) and the phone said *"No Plex media server found on this
account"*. One message, **four** different failures:

- **`includeRelay=1` was missing.** Without the relay address, a phone that is
  not on the server's own network sees a server with **no usable address at
  all** — and the account looks empty. (AC131)
- **`(try? decode) ?? []` swallowed every error.** A decode failure and an
  account without a server are two different problems with two different
  answers.
- **Every field of a resource was required**, so one odd device that left one
  out made the whole answer unreadable — and an unreadable answer was
  reported as *"this account has no media server"*. (AC127)
- **`provides` arrives as a string *and* as a list.** A decoder that knows
  one of them reads **nothing**. (AC128)
- **The HTTP status was never checked.** A refused account (401) was reported
  as an account without a server. It is now *"plex.tv refused the account —
  sign in again at plex.tv/link."* (AC132)
- **The fallback could take the account's own phone for the server.** A device
  that says it is a player is never the media server. (AC129) A resource that
  says nothing about itself is only the server when it answers on a port.
  (AC130)

## The checks

| AC | What it proves | Test |
|----|----------------|------|
| 119 | No rule of the blocker stops a captcha | `AdBlockerTests` |
| 120 | The ad hosts are still stopped | `AdBlockerTests` |
| 121 | A host mentioned in the query is not blocked | `AdBlockerTests` |
| 122 | The CSS rule stays out of every frame | `AdBlockerTests` |
| 123 | A site the user lets through is left alone | `AdBlockerTests` |
| 124 | The site's key is its host without `www.` | `AdBlockerTests` |
| 125 | The exemption is remembered; the blocker can be switched off | `AdBlockerTests` |
| 126 | The tag manager is not blocked | `AdBlockerTests` |
| 133 | A site name is a host name — a glob character is never accepted as an exemption | `AdBlockerTests` |
| 127 | One odd device does not empty the list | `PlexTests` |
| 128 | `provides` reads as a string and as a list | `PlexTests` |
| 129 | The account's own phone is not the media server | `PlexTests` |
| 130 | A silent resource is the server only when it answers on a port | `PlexTests` |
| 131 | The relay address is asked for | `PlexTests` |
| 132 | A refused account is not reported as an account without a server | `PlexTests` |

The rule-matching in `AdBlockerTests` is a **faithful simulation of WebKit's**:
the rules are read in order, `ignore-previous-rules` cancels everything before
it, `if-domain`/`unless-domain` read the **host** (and the hosts under it),
`if-top-url` is a glob and `load-type: ["top-frame"]` only matches the top
frame.

## Files touched

| File | What changed |
|------|--------------|
| `CarTV/Sources/Services/AdBlockerEngine.swift` | `makeRules(exemptSites:)` made **pure** and testable; `if-domain` host matching; the CSS rule is `top-frame`; the tag manager unblocked; `ruleListToApply`, `apply(to:)`, `applyToAllOpenTabs()`, `siteKey(for:)`, `isExempt(_:)`, `setExempt(_:for:)`, `setEnabled(_:)`; the identifier is now `DrivePlayAdBlockerRulesV7` |
| `CarTV/Sources/Services/PlexClient.swift` | `PlexError.noMediaServer` / `.refused(status:)` / `.unreadableAnswer`; `resourcesURL` with `includeRelay=1`; lenient decoding of the resources; the status is read before the body; `preferredServer(in:)` |
| `CarTV/Sources/Views/Settings/AddSourceSheet.swift` | the message comes from the error, not from a fixed string |
| `CarTV/Sources/Views/Browser/InAppBrowserView.swift` | the "Ad Shield" sheet: a master switch and a per-site switch |
| `CarTV/Tests/AdBlockerTests.swift` | **new** — AC119–AC126 |
| `CarTV/Tests/PlexTests.swift` | **new** — AC127–AC132 |
| `docs/SPEC.md`, `CHANGELOG.md`, `AGENTS.md`, `docs/review-2026-11-03.md` | this pass |

## Gotchas learned

- **A content blocker's `url-filter` matches the whole URL.** A host that is
  only *mentioned* in a query string is not a host that is *called* — use
  `if-domain`.
- **The CSS rule of a blocker has to be `top-frame`.** A captcha badge lives in
  a third-party frame.
- **`ignore-previous-rules` has to come last** — it cancels the rules before
  it. That is how an exemption is a rule and not a flag.
- **An exemption is a glob, so a site name has to be a host name.**
  `URL(string: "https://*.evil.com/x")` parses and its host is `*.evil.com`;
  `https://*/` parses too. Written into `*://<site>/*` as it is, such a site
  would let **every** site through — so the name is accepted only when it is
  letters, digits, dashes and dots.
- **The compiled rule list is cached under its identifier.** Bump it with the
  rules, or the new rules are never compiled.
- **Compiling again under the *same* identifier does replace the rules** —
  measured with a real `WKWebView` against a local server: rules A stopped a
  page from loading, rules B compiled under the same identifier let it through.
  So a recompile for a *changed* rule set (an exemption) needs no new name.
- **`compileContentRuleList` calls back on the main queue.** A semaphore on
  the main thread deadlocks.
- **`WKUserContentController` cannot be asked what rule lists it holds.** Test
  the *decision*, not the controller.
- **A `WKWebViewConfiguration` is copied when the web view is made, but its
  `userContentController` is a shared reference** — a rule list added later
  reaches the open web view on the **next** load, so the page must be
  reloaded.
- **A tag manager is not an ad host.** It is the site's own plumbing.
- **plex.tv answers `provides` both as a string and as a list.**
- **`(try? decode) ?? []` turns every error into "no servers".**
- **A server that is not on the phone's network needs its relay address.**

## Still needs a human

* The **SonyLIV sign-in inside the app's browser** — that the captcha appears,
  that it can be solved, and that the OTP is accepted. The tests prove the
  rules no longer stop the captcha; only the page proves the login.
* The **Plex account** — that the server now shows up in the app's source
  sheet. The tests prove the answer is read correctly; only plex.tv proves
  the account.
