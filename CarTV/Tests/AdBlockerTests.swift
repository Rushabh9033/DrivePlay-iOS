import XCTest
import WebKit
@testable import CarTV

/// The ad blocker must not break the login a user came for.
///
/// The truth about the SonyLIV captcha: **no rule ever matched the
/// reCAPTCHA URLs**. The rules broke the page in five other ways, and these
/// tests pin every one of them:
///
/// 1. a `url-filter` matches the **whole URL**, so a page that merely
///    *mentioned* a blocked host in its query string had its own request
///    blocked (`&scrsrc=www.googletagmanager.com`);
/// 2. the CSS rule ran on **every frame**, so it could hide a captcha badge —
///    a captcha lives in a third-party frame;
/// 3. the block rules named the ad hosts with `if-domain`, which reads the
///    **top document's** host and not the host of the request — so they
///    never stopped an ad on a real page at all;
/// 4. there was **no way out**: `isEnabled` was never read, so the user could
///    not let one site through;
/// 5. WebKit compiles the list as **one** thing, so a single value it does
///    not know (`load-type: ["top-frame"]`) killed the **whole** list.
@MainActor
final class AdBlockerTests: XCTestCase {

    // MARK: - The URLs that have to get through

    /// The addresses the sign-in pages of the world load their captcha from.
    private static let captchaURLs = [
        "https://www.google.com/recaptcha/enterprise.js?render=6LeJFSApAAAAAEoReX4JH9-qXmU-0eUYm8h4MWgS",
        "https://www.google.com/recaptcha/api2/anchor?ar=1&k=6LeJFSApAAAAAEoReX4JH9-qXmU-0eUYm8h4MWgS",
        "https://www.google.com/recaptcha/api2/bframe?k=6LeJFSApAAAAAEoReX4JH9-qXmU-0eUYm8h4MWgS",
        "https://www.gstatic.com/recaptcha/releases/enterprise.js",
        "https://www.recaptcha.net/recaptcha/api2/anchor?k=6LeJFSApAAAAAEoReX4JH9-qXmU-0eUYm8h4MWgS",
        "https://hcaptcha.com/1/api.js",
        "https://challenges.cloudflare.com/turnstile/v0/api.js"
    ]

    /// The URLs that have to be stopped.
    private static let adURLs = [
        "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
        "https://securepubads.g.doubleclick.net/tag/js/gpt.js",
        "https://googleads.g.doubleclick.net/pagead/viewthroughconversion/608961644/",
        "https://www.google-analytics.com/analytics.js",
        "https://analytics.google.com/g/collect?v=2&tid=G-1WZE8VR8Q1"
    ]

    // MARK: - The captcha

    /// AC119: **no rule of the blocker stops a captcha.**
    ///
    /// The sign-in of SonyLIV renders reCAPTCHA Enterprise, and the captcha
    /// only works if its script and its frames are allowed through.
    func test_AC119_no_rule_stops_a_captcha() {
        let rules = AdBlockerEngine.makeRules(exemptSites: [])

        for address in Self.captchaURLs {
            let url = URL(string: address)!
            XCTAssertFalse(Self.blocked(rules, by: url),
                           "\(address) is blocked")
        }
    }

    /// AC120: the ad hosts are still stopped.
    ///
    /// The captcha has to get through, but the ads must not: a blocker that
    /// lets everything through is not a blocker. The rules name the ad hosts
    /// with a filter that is anchored to the **host of the request**, because
    /// `if-domain` reads the host of the *page* — a rule for the host of an
    /// image never stopped that image.
    func test_AC120_the_ad_hosts_are_still_stopped() {
        let rules = AdBlockerEngine.makeRules(exemptSites: [])

        for address in Self.adURLs {
            let url = URL(string: address)!
            XCTAssertTrue(Self.blocked(rules, by: url),
                          "\(address) gets through")
        }
    }

    /// AC121: a host that is only **mentioned** is not a host that is
    /// **called**.
    ///
    /// Google's own collector carries `&scrsrc=www.googletagmanager.com` in
    /// its query string. The old rules matched the whole URL, so that
    /// request was stopped by the rule for the tag manager — the page's own
    /// analytics died with it.
    func test_AC121_a_host_mentioned_in_the_query_is_not_blocked() {
        let rules = AdBlockerEngine.makeRules(exemptSites: [])
        let collector = URL(string: "https://www.google.com/ccm/collect?scrsrc=www.googletagmanager.com&hn=www.googleadservices.com")!

        XCTAssertFalse(Self.blocked(rules, by: collector),
                       "a page's own request was stopped by a host it only mentions")

        // The same in a path — the filter is anchored to the host, so
        // nothing after the host can ever match.
        let inPath = URL(string: "https://www.google.com/collect/doubleclick.net.gif")!
        XCTAssertFalse(Self.blocked(rules, by: inPath),
                       "a page's own request was stopped by a host it only mentions")
    }

    /// AC122: the CSS rule hides the ad boxes of the **page** and nothing
    /// else.
    ///
    /// It used to run on every frame, so it could hide a captcha badge — and
    /// a captcha badge lives in a third-party frame. The rule is now
    /// `load-type: ["first-party"]`, which is the page itself and nothing
    /// else (`"top-frame"` is not a load type WebKit knows — one value it
    /// does not know and the whole list is dead), and it excepts the captcha
    /// and identity providers even on the page itself.
    func test_AC122_the_css_rule_stays_out_of_every_frame() {
        let rules = AdBlockerEngine.makeRules(exemptSites: [])
        let cssRules = rules.filter { ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none" }
        XCTAssertEqual(cssRules.count, 1, "there is exactly one CSS rule")

        let trigger = cssRules[0]["trigger"] as? [String: Any]
        XCTAssertEqual(trigger?["load-type"] as? [String], ["first-party"],
                       "the CSS rule must not reach into a frame")

        let excepted = trigger?["unless-domain"] as? [String] ?? []
        for domain in ["google.com", "gstatic.com", "recaptcha.net", "hcaptcha.com",
                       "cloudflare.com", "arkoselabs.com", "funcaptcha.com", "sonyliv.com"] {
            XCTAssertTrue(excepted.contains(domain), "\(domain) is not protected")
        }
        // `unless-domain` matches the **top document's** host exactly, so the
        // `www.` twin has to be named as well.
        XCTAssertTrue(excepted.contains("www.sonyliv.com"),
                      "www.sonyliv.com is not protected")

        // A captcha in a frame of the page: the CSS rule must not touch it.
        let badge = URL(string: "https://www.google.com/recaptcha/api2/bframe?k=abc")!
        let page = URL(string: "https://www.sonyliv.com/account/signin")!
        XCTAssertFalse(Self.matches(cssRules[0], url: badge, page: page),
                       "the CSS rule reaches into a frame")

        // The page itself: the rule still does its job.
        XCTAssertTrue(Self.matches(cssRules[0], url: page, page: page),
                      "the CSS rule does not hide the ad boxes of the page")
    }

    /// AC123: the user can let a site through, and that site is then left
    /// alone.
    ///
    /// A site that needs a captcha to log in is exactly the site that has to
    /// be let through — and the blocker cannot decide that for the user.
    func test_AC123_a_site_the_user_lets_through_is_left_alone() {
        let rules = AdBlockerEngine.makeRules(exemptSites: ["sonyliv.com"])
        let page = URL(string: "https://www.sonyliv.com/account/signin")!
        let ad = URL(string: "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js")!

        // The rule that lets the site through comes **last**, so it wins over
        // the block rules.
        let ignore = rules.enumerated().filter {
            ($0.element["action"] as? [String: Any])?["type"] as? String == "ignore-previous-rules"
        }
        XCTAssertEqual(ignore.count, 1, "the exempt site has one rule")
        XCTAssertEqual(ignore.first?.offset, rules.count - 1, "the exempt rule has to come last")

        // `if-domain` reads the top document's host and matches it exactly,
        // so the `www.` twin is named too.
        let domains = (ignore.first?.element["trigger"] as? [String: Any])?["if-domain"] as? [String]
        XCTAssertEqual(domains, ["sonyliv.com", "www.sonyliv.com"])

        // On that site, nothing is stopped.
        XCTAssertFalse(Self.blocked(rules, by: ad, page: page),
                       "an ad of an exempt site is still stopped")
        // Everywhere else the ads are still stopped.
        XCTAssertTrue(Self.blocked(rules, by: ad),
                      "the exemption leaked out of the site")
    }

    /// AC124: the site a tab is on is the key its exemption is remembered by.
    func test_AC124_the_site_key_is_the_host_without_its_www() {
        XCTAssertEqual(AdBlockerEngine.siteKey(for: URL(string: "https://www.sonyliv.com/account/signin")!),
                       "sonyliv.com")
        XCTAssertEqual(AdBlockerEngine.siteKey(for: URL(string: "https://sonyliv.com")!), "sonyliv.com")
        XCTAssertEqual(AdBlockerEngine.siteKey(for: URL(string: "https://WWW.SonyLIV.com/x")!), "sonyliv.com")
        XCTAssertNil(AdBlockerEngine.siteKey(for: URL(string: "about:blank")!))

        // `www.com` is a host of its own — stripping its `www.` would leave
        // `com`, and an exemption for `com` covers every `.com` host.
        XCTAssertEqual(AdBlockerEngine.siteKey(for: URL(string: "https://www.com/x")!), "www.com")
    }

    /// AC125: the exemption is remembered, and the blocker can be switched
    /// off entirely.
    func test_AC125_the_exemption_is_remembered_and_the_blocker_can_be_switched_off() async {
        let engine = AdBlockerEngine.shared
        let before = engine.exemptSites
        let enabledBefore = engine.isEnabled

        defer {
            for site in engine.exemptSites.subtracting(before) { engine.setExempt(false, for: site) }
            for site in before.subtracting(engine.exemptSites) { engine.setExempt(true, for: site) }
            engine.setEnabled(enabledBefore)
        }

        engine.setExempt(true, for: "sonyliv.com")
        XCTAssertTrue(engine.isExempt("sonyliv.com"))
        XCTAssertTrue(UserDefaults.standard.stringArray(forKey: AdBlockerEngine.exemptSitesKey)?
            .contains("sonyliv.com") ?? false)

        engine.setExempt(false, for: "sonyliv.com")
        XCTAssertFalse(engine.isExempt("sonyliv.com"))

        // The rules are compiled in the background; wait for them, so the
        // switch is tested against real rules and not against "not compiled
        // yet".
        let compiled = expectation(description: "the rules are compiled")
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(20)
            while AdBlockerEngine.shared.compiledRuleList == nil, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
            compiled.fulfill()
        }
        await fulfillment(of: [compiled], timeout: 25)
        XCTAssertNotNil(engine.compiledRuleList, "the rules were never compiled")

        // The master switch: the rules are taken away from every open tab.
        engine.setEnabled(false)
        XCTAssertFalse(engine.isEnabled)
        XCTAssertNil(engine.ruleListToApply, "the rules are handed out while the blocker is off")

        engine.setEnabled(true)
        XCTAssertNotNil(engine.ruleListToApply, "the rules are not handed out when the blocker is on")
    }

    /// AC126: the **tag manager is not blocked.**
    ///
    /// A tag manager is the pipe a site's **own** configuration travels
    /// through — SonyLIV's sign-in page took its login-and-tray setup from
    /// there, and with the tag manager blocked the page lost it. The ad
    /// hosts the tag manager fires at are blocked on their own, so the ads
    /// stay blocked without the page breaking.
    func test_AC126_the_tag_manager_is_not_blocked() {
        let rules = AdBlockerEngine.makeRules(exemptSites: [])
        let tagManager = URL(string: "https://www.googletagmanager.com/gtm.js?id=GTM-MNT9LL")!

        XCTAssertFalse(Self.blocked(rules, by: tagManager),
                       "the site's own tag manager is blocked")
    }

    /// AC133: **a site name is a host name, and nothing else.**
    ///
    /// A site name ends up in a rule as a host, and a host with a glob
    /// character in it matches **other** hosts as well — `*.com` would let
    /// every site through.
    func test_AC133_a_site_name_is_a_host_name_and_nothing_else() {
        // The hosts that are real.
        XCTAssertTrue(AdBlockerEngine.isPlainHost("sonyliv.com"))
        XCTAssertTrue(AdBlockerEngine.isPlainHost("192.168.1.10"))
        XCTAssertTrue(AdBlockerEngine.isPlainHost("my-site.example.co.uk"))

        // The ones that are not: a glob character, a path, a port, a space.
        for bad in ["*", "*.com", "sonyliv.*", "sonyliv.com?", "sonyliv.com/x",
                    "sonyliv.com:443", "sonyliv com", "", ".com", "sonyliv..com",
                    "-sonyliv.com", "sonyliv-.com"] {
            XCTAssertFalse(AdBlockerEngine.isPlainHost(bad), "\(bad) is accepted as a site")
        }

        // And the key of a URL is refused when the host is not a plain host.
        XCTAssertNil(AdBlockerEngine.siteKey(for: URL(string: "https://*.evil.com/x")!))
    }

    /// AC133: **an exemption that is not a host name is refused**, and the
    /// one that is stored is not honoured either.
    func test_AC133_an_exemption_that_is_not_a_host_name_is_refused() {
        let engine = AdBlockerEngine.shared
        let before = engine.exemptSites
        defer {
            for site in engine.exemptSites.subtracting(before) { engine.setExempt(false, for: site) }
            for site in before.subtracting(engine.exemptSites) { engine.setExempt(true, for: site) }
        }

        engine.setExempt(true, for: "*.com")
        XCTAssertFalse(engine.isExempt("*.com"), "a glob was accepted as a site")
        XCTAssertFalse(engine.exemptSites.contains("*.com"))
    }

    /// AC134: **the whole rule list compiles.**
    ///
    /// WebKit compiles the list as **one** thing: a single value it does not
    /// know — `load-type: ["top-frame"]`, or a glob that starts with `*://` —
    /// and the **entire** list is dead. The app then hands out no rules at
    /// all and the blocker does nothing, with only a line in the log to say
    /// so. This test compiles the list the app really hands over and fails
    /// when WebKit refuses it.
    func test_AC134_the_whole_rule_list_compiles() async {
        // With an exemption as well: the exemption's rule is the one that
        // used to break the list.
        for exempt in [Set<String>(), ["sonyliv.com"]] {
            let rules = AdBlockerEngine.makeRules(exemptSites: exempt)
            let json = try! JSONSerialization.data(withJSONObject: rules)
            let encoded = String(data: json, encoding: .utf8)!

            let compiled = expectation(description: "the rules compile")
            var list: WKContentRuleList?
            var failure: Error?
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "AdBlockerTests-\(exempt.isEmpty ? "plain" : "exempt")",
                encodedContentRuleList: encoded
            ) { ruleList, error in
                list = ruleList
                failure = error
                compiled.fulfill()
            }
            await fulfillment(of: [compiled], timeout: 30)

            XCTAssertNil(failure, "the rule list does not compile: \(failure?.localizedDescription ?? "")")
            XCTAssertNotNil(list, "the rule list is not handed over")
        }
    }

    // MARK: - WebKit's matching, in as few lines as it takes

    /// Whether the rules stop a request.
    ///
    /// The rules are read **in order**: a rule that says *"ignore the previous
    /// rules"* cancels every rule before it, which is how a site the user
    /// let through is left alone.
    private static func blocked(_ rules: [[String: Any]],
                                by url: URL,
                                page: URL? = nil) -> Bool {
        let top = page ?? url
        var stopped = false
        for rule in rules {
            guard matches(rule, url: url, page: top) else { continue }
            let type = (rule["action"] as? [String: Any])?["type"] as? String
            if type == "ignore-previous-rules" { return false }
            if type == "block" { stopped = true }
        }
        return stopped
    }

    /// Whether every part of a rule's trigger says yes.
    ///
    /// The parts behave the way **WebKit** behaves — measured against a real
    /// `WKWebView`, not assumed:
    ///
    /// * `url-filter` is a regex over the **whole URL**;
    /// * `if-domain` and `unless-domain` read the **top document's** host and
    ///   match it **exactly**;
    /// * `load-type` knows `"first-party"` (the page's own origin) and
    ///   `"third-party"` (everything else) — and nothing else.
    private static func matches(_ rule: [String: Any], url: URL, page: URL) -> Bool {
        guard let trigger = rule["trigger"] as? [String: Any] else { return false }

        if let filter = trigger["url-filter"] as? String,
           url.absoluteString.range(of: filter, options: .regularExpression) == nil {
            return false
        }
        if let domains = trigger["if-domain"] as? [String],
           !domains.contains(where: { isHost(page, $0) }) {
            return false
        }
        if let domains = trigger["unless-domain"] as? [String],
           domains.contains(where: { isHost(page, $0) }) {
            return false
        }
        if let loadTypes = trigger["load-type"] as? [String] {
            let sameOrigin = page.scheme == url.scheme && page.host == url.host
            if loadTypes.contains("first-party") && !sameOrigin { return false }
            if loadTypes.contains("third-party") && sameOrigin { return false }
        }
        return true
    }

    /// WebKit's `if-domain` / `unless-domain`: the **top document's** host,
    /// matched **exactly** — "sonyliv.com" does not cover "www.sonyliv.com".
    private static func isHost(_ page: URL, _ domain: String) -> Bool {
        page.host?.lowercased() == domain.lowercased()
    }
}
