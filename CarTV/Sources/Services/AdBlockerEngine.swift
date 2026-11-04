import Foundation
import WebKit

@MainActor
public final class AdBlockerEngine: ObservableObject {
    public static let shared = AdBlockerEngine()

    @Published public var isEnabled: Bool = true
    @Published public var totalBlockedCount: Int = 0

    /// The sites the user has let through: the blocker stays on everywhere
    /// else. A site that needs a captcha to log in is one of them.
    @Published public private(set) var exemptSites: Set<String> = []

    /// The hosts whose widgets the CSS rule never hides — the captcha and
    /// identity providers, and the site that reported the broken login.
    ///
    /// `unless-domain` reads the **top document's** host and matches it
    /// **exactly** — a rule that names "sonyliv.com" does not cover
    /// "www.sonyliv.com" — so every host comes with its `www.` twin.
    static let protectedDomains: [String] = [
        "google.com", "gstatic.com", "recaptcha.net", "hcaptcha.com",
        "cloudflare.com", "arkoselabs.com", "funcaptcha.com", "sonyliv.com"
    ].flatMap { [$0, "www.\($0)"] }

    static let exemptSitesKey = "adblocker.exemptSites"
    static let enabledKey = "adblocker.isEnabled"

    public private(set) var compiledRuleList: WKContentRuleList?
    /// The name the compiled rules are stored under.
    ///
    /// **It has to change with the rules.** WebKit keeps the compiled list,
    /// and the app asks for it by name first — a list that was compiled from
    /// the old rules under the old name is found and used, and the new rules
    /// are never even compiled.
    private let ruleListIdentifier = "DrivePlayAdBlockerRulesV8"

    public init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        // A stored exemption that is not a plain host name is thrown away:
        // it would widen the exemption to hosts it was never meant to cover.
        let stored = Set(UserDefaults.standard.stringArray(forKey: Self.exemptSitesKey) ?? [])
        exemptSites = stored.filter { Self.isPlainHost($0) }
        if exemptSites != stored {
            UserDefaults.standard.set(Array(exemptSites).sorted(), forKey: Self.exemptSitesKey)
        }
        loadOrCompileRules()
    }

    /// The master switch. Switching it off takes the rules away from every
    /// open tab; the pages themselves are reloaded by the caller.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        applyToAllOpenTabs()
    }
    
    private func loadOrCompileRules() {
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: ruleListIdentifier) { [weak self] ruleList, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let ruleList = ruleList {
                    print("[AdBlockerEngine] Loaded cached rules: \(ruleList.identifier ?? ruleListIdentifier)")
                    self.compiledRuleList = ruleList
                    self.applyToAllOpenTabs()
                } else {
                    print("[AdBlockerEngine] Compiling rules for \(self.ruleListIdentifier)...")
                    self.compileRules()
                }
            }
        }
    }
    
    private func compileRules() {
        let rules = Self.makeRules(exemptSites: exemptSites)

        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("[AdBlockerEngine] Failed to serialize rules to JSON")
            return
        }

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListIdentifier,
            encodedContentRuleList: jsonString
        ) { [weak self] ruleList, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    print("[AdBlockerEngine] Error compiling rules: \(error)")
                } else if let ruleList = ruleList {
                    print("[AdBlockerEngine] Successfully compiled and loaded \(rules.count) rules!")
                    self.compiledRuleList = ruleList
                }
                // The rules apply to the **next** load, so the pages that are
                // open are loaded again — with the rules that were just
                // compiled, not the ones they had a moment ago.
                self.applyToAllOpenTabs()
            }
        }
    }

    /// The rules the blocker runs, as WebKit wants them.
    ///
    /// Pure, so the tests can read them without a web view: what a rule
    /// matches is the whole difference between a working captcha and a
    /// broken login.
    public static func makeRules(exemptSites: Set<String>) -> [[String: Any]] {
        let domains = [
            // Amazon Ads
            "adtago.s3.amazonaws.com", "analyticsengine.s3.amazonaws.com",
            "analytics.s3.amazonaws.com", "advice-ads.s3.amazonaws.com", "amazon-adsystem.com",
            
            // Google Ads & Syndication
            "pagead2.googlesyndication.com", "adservice.google.com", "adservice.google",
            "pagead2.googleadservices.com", "afs.googlesyndication.com", "googleadservices.com",
            "googlesyndication.com", "ads.google.com",
            
            // Doubleclick
            "stats.g.doubleclick.net", "ad.doubleclick.net", "static.doubleclick.net",
            "m.doubleclick.net", "mediavisor.doubleclick.net", "doubleclick.net",
            "cm.g.doubleclick.net",
            
            // Adcolony
            "ads30.adcolony.com", "adc3-launch.adcolony.com", "events3alt.adcolony.com",
            "wd.adcolony.com", "adcolony.com",
            
            // Media.net
            "static.media.net", "media.net", "adservetx.media.net",
            
            // Google Analytics
            //
            // `googletagmanager.com` is **not** in this list, and that is
            // deliberate. A tag manager is the pipe a site's **own**
            // configuration travels through — SonyLIV's sign-in page took
            // its login-and-tray setup from there, and with the tag manager
            // blocked the page lost it (measured: the rules took 33 of the
            // page's 93 resources away, and the tag manager was one of
            // them). The ad hosts the tag manager fires at — DoubleClick,
            // Google Ads, Google Analytics — are blocked on their own, so
            // the ads stay blocked without the page breaking.
            "analytics.google.com", "click.googleanalytics.com", "google-analytics.com",
            "ssl.google-analytics.com",
            
            // Hotjar
            "adm.hotjar.com", "identify.hotjar.com", "insights.hotjar.com",
            "script.hotjar.com", "surveys.hotjar.com", "careers.hotjar.com",
            "events.hotjar.io", "hotjar.com",
            
            // Mouseflow
            "mouseflow.com", "cdn.mouseflow.com", "o2.mouseflow.com",
            "gtm.mouseflow.com", "api.mouseflow.com", "tools.mouseflow.com", "cdn-test.mouseflow.com",
            
            // Freshworks / Freshmarketer
            "freshmarketer.com", "claritybt.freshmarketer.com", "fwtracks.freshmarketer.com",
            
            // Lucky Orange
            "luckyorange.com", "api.luckyorange.com", "realtime.luckyorange.com",
            "cdn.luckyorange.com", "w1.luckyorange.com", "upload.luckyorange.net",
            "cs.luckyorange.net", "settings.luckyorange.net",
            
            // Stats WP
            "stats.wp.com", "pixel.wp.com",
            
            // Bugsnag & Sentry Error Trackers
            "notify.bugsnag.com", "sessions.bugsnag.com", "api.bugsnag.com",
            "app.bugsnag.com", "bugsnag.com",
            "browser.sentry-cdn.com", "app.getsentry.com", "sentry.io",
            
            // Social Trackers (Facebook, Twitter/X, LinkedIn, Pinterest, Reddit, TikTok)
            "pixel.facebook.com", "an.facebook.com", "connect.facebook.net",
            "static.ads-twitter.com", "ads-api.twitter.com", "ads-twitter.com",
            "ads.linkedin.com", "analytics.pointdrive.linkedin.com", "px.ads.linkedin.com",
            "ads.pinterest.com", "log.pinterest.com", "analytics.pinterest.com", "trk.pinterest.com", "ct.pinterest.com",
            "events.reddit.com", "events.redditmedia.com",
            "ads.youtube.com",
            "ads-api.tiktok.com", "analytics.tiktok.com", "ads-sg.tiktok.com",
            "analytics-sg.tiktok.com", "business-api.tiktok.com", "ads.tiktok.com", "log.byteoversea.com",
            
            // Yahoo & Yandex
            "ads.yahoo.com", "analytics.yahoo.com", "geo.yahoo.com", "udc.yahoo.com",
            "udcm.yahoo.com", "analytics.query.yahoo.com", "partnerads.ysm.yahoo.com",
            "log.fc.yahoo.com", "gemini.yahoo.com", "adtech.yahooinc.com",
            "extmaps-api.yandex.net", "appmetrica.yandex.ru", "adfstat.yandex.ru",
            "metrika.yandex.ru", "offerwall.yandex.net", "adfox.yandex.ru", "mc.yandex.ru",
            
            // Unity Ads
            "auction.unityads.unity3d.com", "webview.unityads.unity3d.com",
            "config.unityads.unity3d.com", "adserver.unityads.unity3d.com", "unityads.unity3d.com",
            
            // OEM Telemetry (Realme, Xiaomi, Oppo, Huawei, OnePlus, Samsung, Apple)
            "iot-eu-logser.realme.com", "iot-logser.realme.com", "bdapi-ads.realmemobile.com", "bdapi-in-ads.realmemobile.com",
            "api.ad.xiaomi.com", "data.mistat.xiaomi.com", "data.mistat.india.xiaomi.com",
            "data.mistat.rus.xiaomi.com", "sdkconfig.ad.xiaomi.com", "sdkconfig.ad.intl.xiaomi.com", "tracking.rus.miui.com",
            "adsfs.oppomobile.com", "adx.ads.oppomobile.com", "ck.ads.oppomobile.com", "data.ads.oppomobile.com",
            "metrics.data.hicloud.com", "metrics2.data.hicloud.com", "grs.hicloud.com", "logservice.hicloud.com", "logservice1.hicloud.com", "logbak.hicloud.com",
            "click.oneplus.cn", "open.oneplus.net",
            "samsungads.com", "smetrics.samsung.com", "nmetrics.samsung.com", "samsung-com.112.2o7.net", "analytics-api.samsunghealthcn.com",
            "iadsdk.apple.com", "metrics.icloud.com", "metrics.mzstatic.com", "api-adservices.apple.com",
            "books-analytics-events.apple.com", "weather-analytics-events.apple.com", "notes-analytics-events.apple.com",
            
            // Major Ad Networks & Header Bidding
            "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "rubiconproject.com",
            "pubmatic.com", "openx.net", "smartadserver.com", "adform.net", "adroll.com",
            "popads.net", "popcash.net", "propellerads.com", "exoclick.com", "juicyads.com",
            "revcontent.com", "trafficjunky.com", "bidswitch.net", "inmobi.com", "vungle.com",
            "applovin.com", "admob.com", "chartboost.com", "ironsrc.com", "yieldmo.com",
            "teads.tv", "sovrn.com", "indexexchange.com", "triplelift.com", "sharethrough.com",
            "gumgum.com", "connatix.com", "zedo.com", "smartclip.net", "flashtalking.com",
            "moatads.com", "serving-sys.com", "adtechus.com", "advertising.com", "mgid.com",
            "adsterra.com", "hilltopads.com", "adblade.com", "buysellads.com", "contextweb.com",
            "infolinks.com", "kargo.com", "lijit.com", "liveintent.com", "nativo.com",
            "realsrv.com", "richaudience.com", "rhythmone.com", "smaato.net", "sonobi.com",
            "spotxchange.com", "spotx.tv", "undertone.com", "unruly.co",
            
            // Analytics & Trackers
            "clarity.ms", "segment.com", "segment.io", "amplitude.com", "mixpanel.com",
            "scorecardresearch.com", "quantserve.com", "quantcount.com", "chartbeat.com",
            "newrelic.com", "nr-data.net", "branch.io", "appsflyer.com", "adjust.com",
            "kochava.com", "crazyegg.com", "optimizely.com", "fullstory.com",
            "heapanalytics.com", "matomo.org", "statcounter.com", "clicky.com",
            "inspectlet.com", "logentries.com", "trackcmp.net", "leadfeeder.com",
            "kissmetrics.com", "woopra.com"
        ]
        
        var rules: [[String: Any]] = []
        for d in domains {
            // The rule has to match the **host of the request** and nothing
            // else.
            //
            // `url-filter` is a regex over the **whole URL**, so a filter
            // that merely *mentions* a host also stops a page that only
            // mentions it in a query string — Google's own collector is
            // stopped by "&scrsrc=www.googletagmanager.com".
            //
            // `if-domain` is no help: it reads the **top document's** host,
            // not the host of the request (measured: a rule for the host of
            // an image never stopped that image, and a rule for the host of
            // the *page* stopped the whole page). It is the right tool for
            // an **exemption** — "leave this site alone" — and the wrong
            // tool for a block.
            //
            // So the filter is anchored to the host:
            // `^https?://([^/]+\.)?<host>(:[0-9]+)?/` — the host has to be
            // the one that is *called*, and a host that only appears later
            // in the URL (a path, a query) can never match.
            let host = d.replacingOccurrences(of: ".", with: "\\.")
            rules.append([
                "trigger": ["url-filter": "^https?://([^/]+\\.)?\(host)(:[0-9]+)?/"],
                "action": ["type": "block"]
            ])
        }

        // Native CSS element hiding for ad banners and video overlays.
        //
        // It hides the ad containers **of the page itself** and nothing
        // else: `load-type: ["first-party"]` keeps it out of every frame,
        // because a captcha badge, a payment form and a consent banner all
        // live in a third-party frame, and hiding one of them breaks the
        // login the user came for. (`"top-frame"` is **not** a load type
        // WebKit knows — it knows `"first-party"` and `"third-party"` and
        // nothing else, and one value it does not know kills the **whole**
        // list.) `unless-domain` protects the captcha and identity
        // providers even on the page itself.
        rules.append([
            "trigger": [
                "url-filter": ".*",
                "load-type": ["first-party"],
                "unless-domain": Self.protectedDomains
            ],
            "action": [
                "type": "css-display-none",
                "selector": ".ad, .ads, .ad-banner, .advertisement, #player-ads, .adsbygoogle, .banner-ad, [class*=\"ad-unit\"], [class*=\"ad-banner\"], [id*=\"google_ads\"], .adbox, .ad_wrapper, .native-ad, .sponsored-post, .ytp-ad-module, .video-ads"
            ]
        ])

        // A site the user has let through: every rule above is ignored for
        // the pages of that site. The rule comes **last**, so it wins.
        //
        // `if-domain` reads the **top document's** host, which is exactly
        // what an exemption needs, and it matches it **exactly** — so the
        // `www.` twin is named as well. (`if-top-url` would need a glob
        // instead, and a glob that starts with `*://` does not even
        // compile — one bad rule and the whole list is dead.)
        for site in exemptSites {
            rules.append([
                "trigger": ["url-filter": ".*", "if-domain": Self.hostVariants(site)],
                "action": ["type": "ignore-previous-rules"]
            ])
        }

        return rules
    }

    /// What a content controller was last given — `nil` when it was given
    /// none.
    private final class AppliedRules {
        let list: WKContentRuleList?
        init(_ list: WKContentRuleList?) { self.list = list }
    }

    /// What each content controller already carries.
    ///
    /// The controller is the key and it is held **weakly** — a closed tab's
    /// controller must not be kept alive by the blocker.
    private var appliedRules = NSMapTable<WKUserContentController, AppliedRules>(
        keyOptions: .weakMemory, valueOptions: .strongMemory)

    /// Applies content rules to a web view configuration.
    ///
    /// **It does nothing when the controller already carries the rules.**
    ///
    /// The rules are applied to the **next** load, and a web view's
    /// `userContentController` is a *shared* reference — so taking the rules
    /// away and putting them back while a page is loading tears the content
    /// process's rule store down under it. The device's own log shows what
    /// that does: the WebKit **GPU process** and three **web content
    /// processes** die with `reason=Crash`, and the tab that was showing the
    /// page is sent back to the start page.
    ///
    /// So the rules are taken **once**, and a navigation that changes nothing
    /// changes nothing here.
    ///
    /// - Returns: `true` when the controller was changed — the caller has to
    ///   load the page again for the change to be seen.
    @discardableResult
    public func apply(to configuration: WKWebViewConfiguration) -> Bool {
        let controller = configuration.userContentController
        let wanted = ruleListToApply
        if let known = appliedRules.object(forKey: controller), known.list === wanted {
            return false
        }
        controller.removeAllContentRuleLists()
        if let wanted {
            controller.add(wanted)
        }
        appliedRules.setObject(AppliedRules(wanted), forKey: controller)
        return true
    }

    /// The rule list the blocker hands to a web view — `nil` when it is
    /// switched off.
    public var ruleListToApply: WKContentRuleList? {
        isEnabled ? compiledRuleList : nil
    }

    /// Re-applies the rules to every open tab and loads the tabs again.
    ///
    /// The rules apply to the **next** load, so a page that is already open
    /// has to be loaded again for the change to be seen — and the rules are
    /// compiled in the background, so the load has to happen **after** the
    /// compile, not before it.
    public func applyToAllOpenTabs() {
        for tab in BrowserTabManager.shared.tabs {
            // The rules apply to the **next** load, so a tab that was given
            // new rules is loaded again — and a tab that was given the same
            // rules is left alone. Reloading every tab for nothing is what
            // used to take the pages down.
            if apply(to: tab.webView.configuration) {
                tab.reload()
            }
        }
    }

    // MARK: - Letting a site through

    /// The host of a URL without its `www.` — the key a site is remembered by.
    ///
    /// `nil` for a host that is not a plain host name: an exemption is used
    /// in a **glob**, and a glob character in a host would widen the
    /// exemption to hosts it was never meant to cover.
    public static func siteKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        var site = host
        if host.hasPrefix("www.") {
            // Only when what is left is still a site of its own: `www.com` is
            // a host, and stripping its `www.` would leave `com` — and an
            // exemption for `com` covers **every** `.com` host.
            let rest = String(host.dropFirst(4))
            if rest.contains(".") { site = rest }
        }
        return isPlainHost(site) ? site : nil
    }

    /// The exact hosts a rule has to name for a site.
    ///
    /// `if-domain` and `unless-domain` read the **top document's** host and
    /// match it **exactly** — "sonyliv.com" does not cover
    /// "www.sonyliv.com" (measured). So a rule that names a site names its
    /// `www.` twin as well.
    static func hostVariants(_ site: String) -> [String] {
        site.hasPrefix("www.") ? [site] : [site, "www.\(site)"]
    }

    /// Whether a string is a plain host name — letters, digits, dashes and
    /// dots, and nothing else.
    ///
    /// The exemption ends up in the rule as a **host**, and a host with a
    /// glob character in it matches **other** hosts as well — `*.com` would
    /// let every site through. `URL(string: "https://*.evil.com/x")` parses
    /// and its host is `*.evil.com`, and `https://*/` parses too — so a site
    /// that is not a plain host name is never accepted.
    static func isPlainHost(_ site: String) -> Bool {
        guard !site.isEmpty, site.count <= 253 else { return false }
        let labels = site.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        for label in labels {
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
        }
        return true
    }

    /// Whether the blocker lets this site through.
    public func isExempt(_ site: String) -> Bool {
        exemptSites.contains(site)
    }

    /// Lets a site through — or puts it back under the rules.
    ///
    /// The rules are compiled again, because the exemption has to be the
    /// **last** rule to win over the block rules.
    public func setExempt(_ exempt: Bool, for site: String) {
        guard Self.isPlainHost(site) else {
            print("[AdBlockerEngine] Not a host name, so not an exemption: \(site)")
            return
        }
        if exempt {
            guard !exemptSites.contains(site) else { return }
            exemptSites.insert(site)
        } else {
            guard exemptSites.contains(site) else { return }
            exemptSites.remove(site)
        }
        UserDefaults.standard.set(Array(exemptSites).sorted(), forKey: Self.exemptSitesKey)
        // The rules are compiled again, because the exemption has to be the
        // **last** rule to win over the block rules. The tabs are loaded
        // again when the compile is done — the rules apply to the next load.
        compileRules()
    }
}
