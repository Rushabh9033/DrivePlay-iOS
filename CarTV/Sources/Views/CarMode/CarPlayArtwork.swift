import AVFoundation
import CarPlay
import SwiftUI
import UIKit

/// The colours the car's screens carry.
///
/// CarPlay renders templates, so the app cannot paint the system's rows. What it
/// *can* paint is the artwork it hands over — and that artwork carries the
/// design: a charcoal tile and the logo at its own aspect ratio.
enum CarPlayPalette {
    /// The card behind a logo.
    static let tile = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    static let white = UIColor.white
}

/// The pictures the car shows.
///
/// A logo is never stretched: it is drawn into the tile with its own aspect
/// ratio, centred on a rounded charcoal card. The tiles are cached, so a
/// category that is rebuilt does not fetch its logos again.
final class CarPlayArtwork {

    static let shared = CarPlayArtwork()

    /// How a logo is fetched. The tests replace it, so nothing goes over the
    /// network while the suite runs.
    var fetchLogo: (URL, @escaping (UIImage?) -> Void) -> Void = { url, completion in
        URLSession.shared.dataTask(with: url) { data, _, _ in
            completion(data.flatMap { UIImage(data: $0) })
        }.resume()
    }

    private let cache = NSCache<NSString, UIImage>()
    /// The drawn tiles, so a rebuilt screen does not draw every card again.
    private let tiles = NSCache<NSString, UIImage>()
    private var inFlight = Set<String>()
    /// The callers that are waiting for a logo that is already on its way.
    private var waiters: [String: [(UIImage?) -> Void]] = [:]
    private let lock = NSLock()

    /// The pictures are asked for one after another — see `fetch`.
    private let gate = DispatchQueue(label: "com.rushabh.cartvv.artwork")
    /// When the next picture may go out.
    private var nextRequest = Date.distantPast
    /// The gap between two logo requests.
    private static let requestGap: TimeInterval = 0.2
    /// How many times a picture is asked for before it is given up on.
    private static let fetchAttempts = 3

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        // A card is drawn for the **car's** screen, so it is a big picture —
        // and a screen of them is bigger than the logo cache. A limit that is
        // too small makes the cache throw the cards away and draw them again
        // on the next rebuild, which is the stall this cache exists to avoid.
        tiles.totalCostLimit = 128 * 1024 * 1024
    }

    /// The size a list row's artwork is drawn at.
    static var rowSize: CGSize { CPListItem.maximumImageSize }

    /// The size a card's artwork is drawn at.
    static var cardSize: CGSize {
        if #available(iOS 26.0, *) {
            return CPListImageRowItemCardElement.maximumImageSize
        }
        return CPListItem.maximumImageSize
    }

    /// The scale of the car's screen.
    ///
    /// Apple says it plainly: *"images you display in any template should be
    /// sized to a display scale matching the scale of the `carTraitCollection`,
    /// not the scale of the iOS device's main screen."* The car's screen is a
    /// different display — often a different aspect ratio and a different
    /// scale — so the artwork is drawn for it, not for the phone.
    static var displayScale: CGFloat = UITraitCollection.current.displayScale

    /// The tile for a channel — the logo when it is already cached, the drawn
    /// placeholder otherwise.
    ///
    /// The logo cache holds the *logo*, so one fetch serves every size the car
    /// asks for; the tile cache holds the drawn card, so a screen that is
    /// rebuilt (a favourite toggled, a logo arriving) does not draw every card
    /// again — with thousands of channels that is the difference between a
    /// rebuild and a stall.
    func tile(for channel: Channel, size: CGSize) -> UIImage {
        tile(for: channel, logo: logo(for: channel), size: size)
    }

    /// The tile for a channel, drawn from a logo that is in hand.
    ///
    /// The logo is **the one that arrived**, never a lookup in the cache: the
    /// logo cache is bounded and it throws the oldest pictures away, so a
    /// lookup can come back empty for a logo that was handed over a moment
    /// ago — and the card would show the initials instead of the channel's own
    /// picture.
    func tile(for channel: Channel, logo: UIImage?, size: CGSize) -> UIImage {
        let key = Self.tileKey(for: channel, size: size, hasLogo: logo != nil)
        if let cached = tiles.object(forKey: key as NSString) { return cached }

        let image = Self.draw(logo: logo, initials: channel.name, size: size)
        tiles.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
        // The placeholder this card replaces is not kept: two cards per
        // channel is two times the memory, and the car never shows the
        // placeholder again.
        if logo != nil {
            tiles.removeObject(
                forKey: Self.tileKey(for: channel, size: size, hasLogo: false) as NSString)
        }
        return image
    }

    /// Fetches the channel's own logo and hands it over.
    ///
    /// The completion runs on the main thread with the logo — or with `nil`
    /// when the channel has no logo or the download failed. A logo that is
    /// already in the cache is handed over at once: it is not news, but the
    /// caller still wants the card that shows it.
    ///
    /// One download per logo, however many callers ask for it: the callers
    /// that arrive while the download is on its way are kept and served when
    /// it lands.
    func loadLogo(for channel: Channel, completion: @escaping (UIImage?) -> Void) {
        let key = Self.key(for: channel)
        if let cached = cache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        guard let logoURL = channel.logoURL else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        lock.lock()
        if inFlight.contains(key) {
            waiters[key, default: []].append(completion)
            lock.unlock()
            return
        }
        inFlight.insert(key)
        waiters[key] = [completion]
        lock.unlock()

        fetch(logoURL, attempt: 1) { [weak self] logo in
            guard let self else { return }
            if let logo {
                self.cache.setObject(logo, forKey: key as NSString, cost: Self.cost(of: logo))
            }
            self.lock.lock()
            let callbacks = self.waiters.removeValue(forKey: key) ?? []
            self.inFlight.remove(key)
            self.lock.unlock()
            DispatchQueue.main.async {
                for callback in callbacks { callback(logo) }
            }
        }
    }

    /// Fetches a logo — and tries again when the server refuses it.
    ///
    /// The playlist's logos come from a handful of CDNs, and the biggest of
    /// them (imgur) answers **429** when more than a hundred pictures are
    /// asked for in a short while. The car asks for a whole category at once,
    /// so a refusal is the rule rather than the exception — and the picture it
    /// refused is worth another try a moment later.
    ///
    /// The requests go out **one after another**, with a gap between them: the
    /// rows that are on the car come first, and the rest of the category
    /// follows instead of arriving as one burst that is refused as a whole.
    private func fetch(_ url: URL, attempt: Int, completion: @escaping (UIImage?) -> Void) {
        gate.async {
            let now = Date()
            // The next request goes out when its turn comes — never before,
            // and never later than the gap after the one before it.
            let start = max(now, self.nextRequest)
            self.nextRequest = start.addingTimeInterval(Self.requestGap)
            self.gate.asyncAfter(deadline: .now() + start.timeIntervalSince(now)) {
                self.fetchLogo(url) { logo in
                    guard logo == nil, attempt < Self.fetchAttempts else {
                        completion(logo)
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt) * 2) {
                        self.fetch(url, attempt: attempt + 1, completion: completion)
                    }
                }
            }
        }
    }

    /// The tile for a site of the browser catalogue.
    ///
    /// The tile is **drawn**, not fetched — but the browser draws a row of
    /// them on every keystroke, at the car's scale, so it is cached like the
    /// channel tiles are.
    func siteTile(for site: BookmarkItem, size: CGSize) -> UIImage {
        let key = "site|\(site.urlString)|\(Int(size.width))x\(Int(size.height))|\(Self.displayScale)" as NSString
        if let cached = tiles.object(forKey: key) { return cached }

        let background = UIColor(site.iconBgColor)
        let image: UIImage
        if let symbol = site.systemImage,
           let symbolImage = UIImage(systemName: symbol)?.withTintColor(UIColor(site.labelColor), renderingMode: .alwaysOriginal) {
            image = Self.draw(symbol: symbolImage, background: background, size: size)
        } else {
            image = Self.draw(text: site.labelText ?? site.name, color: UIColor(site.labelColor), background: background, size: size)
        }
        tiles.setObject(image, forKey: key, cost: Self.cost(of: image))
        return image
    }

    /// The channel's own logo, when it has been fetched already.
    private func logo(for channel: Channel) -> UIImage? {
        cache.object(forKey: Self.key(for: channel) as NSString)
    }

    private static func key(for channel: Channel) -> String {
        channel.logoURL?.absoluteString ?? channel.name
    }

    /// The key of a drawn tile — the channel, the size, the scale and whether
    /// the logo is in yet (the placeholder and the logo are different cards).
    private static func tileKey(for channel: Channel, size: CGSize, hasLogo: Bool) -> String {
        "\(key(for: channel))|\(Int(size.width))x\(Int(size.height))|\(displayScale)|\(hasLogo)"
    }

    /// What a picture costs in the cache — its **pixels**, not its points.
    ///
    /// Points understate a picture by the square of the scale, so a cache that
    /// counts them throws the pictures away nine times sooner than its limit
    /// says.
    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels * 4)
    }

    // MARK: - Drawing

    /// A charcoal card with the logo at its own aspect ratio — never stretched.
    static func draw(logo: UIImage?, initials: String, size: CGSize) -> UIImage {
        let canvas = canvas(for: size)
        return draw(background: CarPlayPalette.tile, canvas: canvas) { rect in
            if let logo {
                logo.draw(in: logoRect(logoSize: logo.size, in: rect))
            } else {
                drawText(String(initials.uppercased().prefix(3)),
                         color: CarPlayPalette.white,
                         size: CGSize(width: rect.width * 0.34, height: rect.height * 0.34),
                         in: rect)
            }
        }
    }

    /// The area a logo is drawn in — the logo keeps its own aspect ratio and
    /// stays inside the card, so it is never stretched and never clipped.
    static func logoRect(logoSize: CGSize, in rect: CGRect) -> CGRect {
        let inset = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
        return AVMakeRect(aspectRatio: logoSize, insideRect: inset)
    }

    /// A card with a symbol on it — the browser catalogue's own icons.
    static func draw(symbol: UIImage, background: UIColor, size: CGSize) -> UIImage {
        let canvas = canvas(for: size)
        return draw(background: background, canvas: canvas) { rect in
            symbol.draw(in: logoRect(logoSize: symbol.size, in: rect))
        }
    }

    /// A card with a letter on it.
    static func draw(text: String, color: UIColor, background: UIColor, size: CGSize) -> UIImage {
        let canvas = canvas(for: size)
        return draw(background: background, canvas: canvas) { rect in
            drawText(String(text.prefix(3)),
                     color: color,
                     size: CGSize(width: rect.width * 0.34, height: rect.height * 0.34),
                     in: rect)
        }
    }

    /// The card itself: a rounded charcoal tile with the logo on it.
    ///
    /// Nothing else is drawn on it. The car's screen is dark, and a card with
    /// a colour of our own on it reads as a bug on the car, not as a design.
    private static func draw(background: UIColor,
                             canvas: CGRect,
                             content: (CGRect) -> Void) -> UIImage {
        // The canvas is in points; the renderer draws it at the **car's**
        // scale, so the pixels the car shows are the ones that were drawn.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = displayScale
        let renderer = UIGraphicsImageRenderer(size: canvas.size, format: format)
        return renderer.image { context in
            context.cgContext.setFillColor(background.cgColor)
            context.cgContext.addPath(UIBezierPath(roundedRect: canvas, cornerRadius: canvas.width * 0.12).cgPath)
            context.cgContext.fillPath()

            content(canvas)
        }
    }

    /// The drawing surface — the size the car expects, so the system does not
    /// resize (and thereby distort) the artwork.
    private static func canvas(for size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0,
               width: max(size.width, 32),
               height: max(size.height, 32))
    }

    private static func drawText(_ text: String, color: UIColor, size: CGSize, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.width, weight: .bold),
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: rect.midX - textSize.width / 2,
                        y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }
}
