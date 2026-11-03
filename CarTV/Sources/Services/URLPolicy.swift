import Foundation

/// How a server address becomes a URL.
///
/// Plain HTTP is only used for hosts on the local network; every other host has
/// to use HTTPS. App Transport Security enforces the same rule at runtime, so
/// the two have to agree — otherwise the app builds a URL that the system then
/// refuses to load.
public enum URLPolicy {

    /// The scheme to use for an address that has none.
    public static func scheme(forHost host: String) -> String {
        isLocalHost(host) ? "http" : "https"
    }

    /// Whether the host is on the local network, where plain HTTP is allowed.
    ///
    /// This is the set App Transport Security exempts under
    /// `NSAllowsLocalNetworking`: unqualified names, `.local` names, the private
    /// IPv4 ranges, link-local addresses and loopback.
    public static func isLocalHost(_ host: String) -> Bool {
        var h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("[") && h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if h == "localhost" || h.hasSuffix(".local") { return true }
        if h.contains(":") {
            // IPv6 literal: only loopback and link-local are local.
            return h == "::1" || h.hasPrefix("fe80:")
        }
        let octets = h.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, let second) where (16...31).contains(second):
            return true
        default:
            return false
        }
    }

    /// The host of an address, without scheme, port or path.
    public static func host(of address: String) -> String {
        var h = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = h.range(of: "://") { h = String(h[range.upperBound...]) }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if h.hasPrefix("[") { return h }              // bracketed IPv6 literal
        if h.filter({ $0 == ":" }).count > 1 { return h }  // bare IPv6 literal
        if let colon = h.lastIndex(of: ":") { h = String(h[..<colon]) }
        return h
    }

    /// A server address with a scheme and without a trailing slash.
    public static func normalized(_ address: String) -> String {
        var base = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return base }
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "\(scheme(forHost: host(of: base)))://\(base)"
        }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    /// A message the user can act on when a request fails.
    ///
    /// App Transport Security refuses an unencrypted public address, and the
    /// system error does not say what to do about it.
    public static func message(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return "iOS blocked this address because it uses an unencrypted connection (http://). Use https:// — or, for a server on your own network, its local address."
        }
        return error.localizedDescription
    }
}
