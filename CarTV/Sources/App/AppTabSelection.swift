import Combine

/// The tabs of the app.
public enum MainTab: Int, Hashable, CaseIterable {
    case home = 0
    case browser = 1
    case vault = 2
    case cockpit = 3
    case settings = 4
}

/// The tab the app shows.
///
/// The tab used to be a `@State` **inside** `MainTabView` — which meant that
/// nothing outside the view could change it. The car asked for a page, the
/// page opened on the phone's browser tab, and the phone stayed on the tab it
/// was on: the car asked and nothing happened on either screen.
///
/// It has to be shared, because the share the car needs captures **the
/// phone's screen** — so the page the car asked for has to be *on* the
/// screen, not on a tab the user cannot see.
@MainActor
public final class AppTabSelection: ObservableObject {
    public static let shared = AppTabSelection()

    /// The tab the app shows.
    @Published public var tab: MainTab = .home

    private init() {}
}
