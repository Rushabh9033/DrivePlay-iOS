import Foundation
import WebKit

@MainActor
public final class AdBlockerEngine: ObservableObject {
    public static let shared = AdBlockerEngine()
    
    @Published public var isEnabled: Bool = true
    @Published public var totalBlockedCount: Int = 0
    
    public private(set) var compiledRuleList: WKContentRuleList?
    private let ruleListIdentifier = "DrivePlayAdBlockerRulesV5"
    
    public init() {
        loadOrCompileRules()
    }
    
    private func loadOrCompileRules() {
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: ruleListIdentifier) { [weak self] ruleList, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let ruleList = ruleList {
                    print("[AdBlockerEngine] Loaded cached rules: \(ruleList.identifier)")
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
        let domains = [
            // Amazon Ads
            "adtago\\.s3\\.amazonaws\\.com", "analyticsengine\\.s3\\.amazonaws\\.com",
            "analytics\\.s3\\.amazonaws\\.com", "advice-ads\\.s3\\.amazonaws\\.com", "amazon-adsystem\\.com",
            
            // Google Ads & Syndication
            "pagead2\\.googlesyndication\\.com", "adservice\\.google\\.com", "adservice\\.google",
            "pagead2\\.googleadservices\\.com", "afs\\.googlesyndication\\.com", "googleadservices\\.com",
            "googlesyndication\\.com", "ads\\.google\\.com",
            
            // Doubleclick
            "stats\\.g\\.doubleclick\\.net", "ad\\.doubleclick\\.net", "static\\.doubleclick\\.net",
            "m\\.doubleclick\\.net", "mediavisor\\.doubleclick\\.net", "doubleclick\\.net",
            "cm\\.g\\.doubleclick\\.net",
            
            // Adcolony
            "ads30\\.adcolony\\.com", "adc3-launch\\.adcolony\\.com", "events3alt\\.adcolony\\.com",
            "wd\\.adcolony\\.com", "adcolony\\.com",
            
            // Media.net
            "static\\.media\\.net", "media\\.net", "adservetx\\.media\\.net",
            
            // Google Analytics
            "analytics\\.google\\.com", "click\\.googleanalytics\\.com", "google-analytics\\.com",
            "ssl\\.google-analytics\\.com", "googletagmanager\\.com",
            
            // Hotjar
            "adm\\.hotjar\\.com", "identify\\.hotjar\\.com", "insights\\.hotjar\\.com",
            "script\\.hotjar\\.com", "surveys\\.hotjar\\.com", "careers\\.hotjar\\.com",
            "events\\.hotjar\\.io", "hotjar\\.com",
            
            // Mouseflow
            "mouseflow\\.com", "cdn\\.mouseflow\\.com", "o2\\.mouseflow\\.com",
            "gtm\\.mouseflow\\.com", "api\\.mouseflow\\.com", "tools\\.mouseflow\\.com", "cdn-test\\.mouseflow\\.com",
            
            // Freshworks / Freshmarketer
            "freshmarketer\\.com", "claritybt\\.freshmarketer\\.com", "fwtracks\\.freshmarketer\\.com",
            
            // Lucky Orange
            "luckyorange\\.com", "api\\.luckyorange\\.com", "realtime\\.luckyorange\\.com",
            "cdn\\.luckyorange\\.com", "w1\\.luckyorange\\.com", "upload\\.luckyorange\\.net",
            "cs\\.luckyorange\\.net", "settings\\.luckyorange\\.net",
            
            // Stats WP
            "stats\\.wp\\.com", "pixel\\.wp\\.com",
            
            // Bugsnag & Sentry Error Trackers
            "notify\\.bugsnag\\.com", "sessions\\.bugsnag\\.com", "api\\.bugsnag\\.com",
            "app\\.bugsnag\\.com", "bugsnag\\.com",
            "browser\\.sentry-cdn\\.com", "app\\.getsentry\\.com", "sentry\\.io",
            
            // Social Trackers (Facebook, Twitter/X, LinkedIn, Pinterest, Reddit, TikTok)
            "pixel\\.facebook\\.com", "an\\.facebook\\.com", "connect\\.facebook\\.net",
            "static\\.ads-twitter\\.com", "ads-api\\.twitter\\.com", "ads-twitter\\.com",
            "ads\\.linkedin\\.com", "analytics\\.pointdrive\\.linkedin\\.com", "px\\.ads\\.linkedin\\.com",
            "ads\\.pinterest\\.com", "log\\.pinterest\\.com", "analytics\\.pinterest\\.com", "trk\\.pinterest\\.com", "ct\\.pinterest\\.com",
            "events\\.reddit\\.com", "events\\.redditmedia\\.com",
            "ads\\.youtube\\.com",
            "ads-api\\.tiktok\\.com", "analytics\\.tiktok\\.com", "ads-sg\\.tiktok\\.com",
            "analytics-sg\\.tiktok\\.com", "business-api\\.tiktok\\.com", "ads\\.tiktok\\.com", "log\\.byteoversea\\.com",
            
            // Yahoo & Yandex
            "ads\\.yahoo\\.com", "analytics\\.yahoo\\.com", "geo\\.yahoo\\.com", "udc\\.yahoo\\.com",
            "udcm\\.yahoo\\.com", "analytics\\.query\\.yahoo\\.com", "partnerads\\.ysm\\.yahoo\\.com",
            "log\\.fc\\.yahoo\\.com", "gemini\\.yahoo\\.com", "adtech\\.yahooinc\\.com",
            "extmaps-api\\.yandex\\.net", "appmetrica\\.yandex\\.ru", "adfstat\\.yandex\\.ru",
            "metrika\\.yandex\\.ru", "offerwall\\.yandex\\.net", "adfox\\.yandex\\.ru", "mc\\.yandex\\.ru",
            
            // Unity Ads
            "auction\\.unityads\\.unity3d\\.com", "webview\\.unityads\\.unity3d\\.com",
            "config\\.unityads\\.unity3d\\.com", "adserver\\.unityads\\.unity3d\\.com", "unityads\\.unity3d\\.com",
            
            // OEM Telemetry (Realme, Xiaomi, Oppo, Huawei, OnePlus, Samsung, Apple)
            "iot-eu-logser\\.realme\\.com", "iot-logser\\.realme\\.com", "bdapi-ads\\.realmemobile\\.com", "bdapi-in-ads\\.realmemobile\\.com",
            "api\\.ad\\.xiaomi\\.com", "data\\.mistat\\.xiaomi\\.com", "data\\.mistat\\.india\\.xiaomi\\.com",
            "data\\.mistat\\.rus\\.xiaomi\\.com", "sdkconfig\\.ad\\.xiaomi\\.com", "sdkconfig\\.ad\\.intl\\.xiaomi\\.com", "tracking\\.rus\\.miui\\.com",
            "adsfs\\.oppomobile\\.com", "adx\\.ads\\.oppomobile\\.com", "ck\\.ads\\.oppomobile\\.com", "data\\.ads\\.oppomobile\\.com",
            "metrics\\.data\\.hicloud\\.com", "metrics2\\.data\\.hicloud\\.com", "grs\\.hicloud\\.com", "logservice\\.hicloud\\.com", "logservice1\\.hicloud\\.com", "logbak\\.hicloud\\.com",
            "click\\.oneplus\\.cn", "open\\.oneplus\\.net",
            "samsungads\\.com", "smetrics\\.samsung\\.com", "nmetrics\\.samsung\\.com", "samsung-com\\.112\\.2o7\\.net", "analytics-api\\.samsunghealthcn\\.com",
            "iadsdk\\.apple\\.com", "metrics\\.icloud\\.com", "metrics\\.mzstatic\\.com", "api-adservices\\.apple\\.com",
            "books-analytics-events\\.apple\\.com", "weather-analytics-events\\.apple\\.com", "notes-analytics-events\\.apple\\.com",
            
            // Major Ad Networks & Header Bidding
            "criteo\\.com", "criteo\\.net", "taboola\\.com", "outbrain\\.com", "rubiconproject\\.com",
            "pubmatic\\.com", "openx\\.net", "smartadserver\\.com", "adform\\.net", "adroll\\.com",
            "popads\\.net", "popcash\\.net", "propellerads\\.com", "exoclick\\.com", "juicyads\\.com",
            "revcontent\\.com", "trafficjunky\\.com", "bidswitch\\.net", "inmobi\\.com", "vungle\\.com",
            "applovin\\.com", "admob\\.com", "chartboost\\.com", "ironsrc\\.com", "yieldmo\\.com",
            "teads\\.tv", "sovrn\\.com", "indexexchange\\.com", "triplelift\\.com", "sharethrough\\.com",
            "gumgum\\.com", "connatix\\.com", "zedo\\.com", "smartclip\\.net", "flashtalking\\.com",
            "moatads\\.com", "serving-sys\\.com", "adtechus\\.com", "advertising\\.com", "mgid\\.com",
            "adsterra\\.com", "hilltopads\\.com", "adblade\\.com", "buysellads\\.com", "contextweb\\.com",
            "infolinks\\.com", "kargo\\.com", "lijit\\.com", "liveintent\\.com", "nativo\\.com",
            "realsrv\\.com", "richaudience\\.com", "rhythmone\\.com", "smaato\\.net", "sonobi\\.com",
            "spotxchange\\.com", "spotx\\.tv", "undertone\\.com", "unruly\\.co",
            
            // Analytics & Trackers
            "clarity\\.ms", "segment\\.com", "segment\\.io", "amplitude\\.com", "mixpanel\\.com",
            "scorecardresearch\\.com", "quantserve\\.com", "quantcount\\.com", "chartbeat\\.com",
            "newrelic\\.com", "nr-data\\.net", "branch\\.io", "appsflyer\\.com", "adjust\\.com",
            "kochava\\.com", "crazyegg\\.com", "optimizely\\.com", "fullstory\\.com",
            "heapanalytics\\.com", "matomo\\.org", "statcounter\\.com", "clicky\\.com",
            "inspectlet\\.com", "logentries\\.com", "trackcmp\\.net", "leadfeeder\\.com",
            "kissmetrics\\.com", "woopra\\.com"
        ]
        
        var rules: [[String: Any]] = []
        for d in domains {
            rules.append([
                "trigger": ["url-filter": d],
                "action": ["type": "block"]
            ])
        }
        
        // Native CSS element hiding for ad banners and video overlays
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": ".ad, .ads, .ad-banner, .advertisement, #player-ads, .adsbygoogle, .banner-ad, [class*=\"ad-unit\"], [class*=\"ad-banner\"], [id*=\"google_ads\"], .adbox, .ad_wrapper, .native-ad, .sponsored-post, .ytp-ad-module, .video-ads"
            ]
        ])
        
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
                    self.applyToAllOpenTabs()
                }
            }
        }
    }
    
    /// Applies content rules to a web view configuration
    public func apply(to configuration: WKWebViewConfiguration) {
        if let ruleList = compiledRuleList {
            configuration.userContentController.removeAllContentRuleLists()
            configuration.userContentController.add(ruleList)
        }
    }
    
    /// Re-applies active rules across all currently open tabs
    public func applyToAllOpenTabs() {
        guard let ruleList = compiledRuleList else { return }
        for tab in BrowserTabManager.shared.tabs {
            tab.webView.configuration.userContentController.removeAllContentRuleLists()
            tab.webView.configuration.userContentController.add(ruleList)
        }
    }
}
