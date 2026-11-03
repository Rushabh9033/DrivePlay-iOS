import AVFoundation
import CarPlay
import SwiftUI
import UIKit

/// The colours the car's screens carry.
///
/// CarPlay renders templates, so the app cannot paint the system's rows. What it
/// *can* paint is the artwork it hands over — and that artwork carries the
/// design: a charcoal tile, the logo at its own aspect ratio and the green
/// accent.
enum CarPlayPalette {
    /// The card behind a logo.
    static let tile = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    /// The green the reference interface uses for the active marker.
    static let accent = UIColor(red: 0.18, green: 0.82, blue: 0.35, alpha: 1)
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
    private let lock = NSLock()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        tiles.totalCostLimit = 32 * 1024 * 1024
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
        let logo = logo(for: channel)
        let key = Self.tileKey(for: channel, size: size, hasLogo: logo != nil)
        if let cached = tiles.object(forKey: key as NSString) { return cached }

        let image = Self.draw(logo: logo, initials: channel.name, size: size)
        tiles.setObject(image, forKey: key as NSString,
                        cost: Int(image.size.width * image.size.height * image.scale * image.scale))
        return image
    }

    /// Fetches the channel's own logo.
    ///
    /// The completion runs **only when something was fetched** — a logo that is
    /// already in the cache is not news, and a completion that fired on every
    /// cache hit would rebuild the template for ever.
    func fetchTile(for channel: Channel, completion: @escaping () -> Void) {
        let key = Self.key(for: channel)
        if cache.object(forKey: key as NSString) != nil { return }
        guard let logoURL = channel.logoURL else { return }

        lock.lock()
        let alreadyFetching = inFlight.contains(key)
        if !alreadyFetching { inFlight.insert(key) }
        lock.unlock()
        if alreadyFetching { return }

        fetchLogo(logoURL) { [weak self] logo in
            guard let logo else {
                self?.finish(key)
                return
            }
            self?.cache.setObject(logo, forKey: key as NSString,
                                  cost: Int(logo.size.width * logo.size.height * 4))
            self?.finish(key)
            DispatchQueue.main.async { completion() }
        }
    }

    /// The tile for a site of the browser catalogue.
    func siteTile(for site: BookmarkItem, size: CGSize) -> UIImage {
        let background = UIColor(site.iconBgColor)
        if let symbol = site.systemImage,
           let image = UIImage(systemName: symbol)?.withTintColor(UIColor(site.labelColor), renderingMode: .alwaysOriginal) {
            return Self.draw(symbol: image, background: background, size: size)
        }
        return Self.draw(text: site.labelText ?? site.name, color: UIColor(site.labelColor), background: background, size: size)
    }

    private func finish(_ key: String) {
        lock.lock()
        inFlight.remove(key)
        lock.unlock()
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

    // MARK: - Drawing

    /// A charcoal card with the logo at its own aspect ratio — never stretched.
    static func draw(logo: UIImage?, initials: String, size: CGSize) -> UIImage {
        let canvas = canvas(for: size)
        return draw(background: CarPlayPalette.tile, accent: CarPlayPalette.accent, canvas: canvas) { rect in
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
        return draw(background: background, accent: CarPlayPalette.accent, canvas: canvas) { rect in
            symbol.draw(in: logoRect(logoSize: symbol.size, in: rect))
        }
    }

    /// A card with a letter on it.
    static func draw(text: String, color: UIColor, background: UIColor, size: CGSize) -> UIImage {
        let canvas = canvas(for: size)
        return draw(background: background, accent: CarPlayPalette.accent, canvas: canvas) { rect in
            drawText(String(text.prefix(3)),
                     color: color,
                     size: CGSize(width: rect.width * 0.34, height: rect.height * 0.34),
                     in: rect)
        }
    }

    /// The card itself: a rounded charcoal tile with the green marker.
    private static func draw(background: UIColor,
                             accent: UIColor,
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

            // The green marker along the bottom of the card.
            context.cgContext.setFillColor(accent.cgColor)
            context.cgContext.fill(CGRect(x: 0,
                                         y: canvas.height - max(2, canvas.height * 0.02),
                                         width: canvas.width,
                                         height: max(2, canvas.height * 0.02)))
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
