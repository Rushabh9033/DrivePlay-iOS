import SwiftUI

/// The sites the in-app browser offers.
///
/// The list lives here and not inside the view, so the phone's browser and the
/// car's browser tab show **the same** sites — one list, no second copy to keep
/// in step.
public enum BrowserCatalog {

    public static let liveAndSports: [BookmarkItem] = [
        BookmarkItem(name: "Famelack", urlString: "https://famelack.com", iconBgColor: .black, labelText: "FL", labelColor: .white),
        BookmarkItem(name: "Twitch", urlString: "https://m.twitch.tv", iconBgColor: Color(red: 0.57, green: 0.27, blue: 1.0), systemImage: "bubble.left.and.bubble.right.fill"),
        BookmarkItem(name: "Pluto TV", urlString: "https://pluto.tv", iconBgColor: Color(red: 0.28, green: 0.05, blue: 0.55), labelText: "P>", labelColor: .yellow)
    ]

    public static let gamesAndTools: [BookmarkItem] = [
        BookmarkItem(name: "Game", urlString: "https://poki.com", iconBgColor: Color(red: 0.25, green: 0.52, blue: 1.0), systemImage: "gamecontroller.fill"),
        BookmarkItem(name: "Google", urlString: "https://google.com", iconBgColor: .white, labelText: "G", labelColor: Color(red: 0.26, green: 0.52, blue: 0.96))
    ]

    public static let videoAndMusic: [BookmarkItem] = [
        BookmarkItem(name: "YouTube", urlString: "https://m.youtube.com", iconBgColor: Color(red: 0.95, green: 0.1, blue: 0.1), systemImage: "play.fill"),
        BookmarkItem(name: "Hotstar", urlString: "https://hotstar.com", iconBgColor: Color(red: 0.06, green: 0.12, blue: 0.25), systemImage: "sparkles", labelColor: .yellow),
        BookmarkItem(name: "Sony LIV", urlString: "https://sonyliv.com", iconBgColor: Color(red: 0.04, green: 0.08, blue: 0.18), labelText: "liv", labelColor: .yellow),
        BookmarkItem(name: "ZEE5", urlString: "https://zee5.com", iconBgColor: Color(red: 0.14, green: 0.14, blue: 0.16), labelText: "Z5", labelColor: .white),
        BookmarkItem(name: "Prime Video", urlString: "https://primevideo.com", iconBgColor: Color(red: 0.05, green: 0.65, blue: 0.9), systemImage: "arrow.right.circle.fill"),
        BookmarkItem(name: "iQIYI International", urlString: "https://iq.com", iconBgColor: Color(red: 0.0, green: 0.78, blue: 0.38), labelText: "iQIYI", labelColor: .white),
        BookmarkItem(name: "TikTok", urlString: "https://tiktok.com", iconBgColor: .black, systemImage: "music.note"),
        BookmarkItem(name: "Vimeo", urlString: "https://vimeo.com", iconBgColor: Color(red: 0.1, green: 0.72, blue: 0.92), labelText: "v", labelColor: .white),
        BookmarkItem(name: "Dailymotion", urlString: "https://dailymotion.com", iconBgColor: Color(red: 0.0, green: 0.42, blue: 0.88), labelText: "d", labelColor: .white),
        BookmarkItem(name: "Instagram", urlString: "https://instagram.com", iconBgColor: Color(red: 0.85, green: 0.15, blue: 0.45), systemImage: "camera.fill"),
        BookmarkItem(name: "HBO Max", urlString: "https://max.com", iconBgColor: Color(red: 0.22, green: 0.05, blue: 0.5), labelText: "max", labelColor: .white),
        BookmarkItem(name: "Peacock", urlString: "https://peacocktv.com", iconBgColor: Color(red: 0.05, green: 0.5, blue: 0.95), systemImage: "circle.grid.cross.fill")
    ]

    /// The groups, in the order the browser shows them.
    public static let groups: [(title: String, items: [BookmarkItem])] = [
        ("Live & Sports", liveAndSports),
        ("Games & Tools", gamesAndTools),
        ("Video & Music", videoAndMusic)
    ]
}
