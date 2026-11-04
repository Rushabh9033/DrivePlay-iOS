import Foundation
import Security

/// The secrets of one source.
///
/// These live in the Keychain, never in a plist or a JSON file: a device backup
/// or a file-sharing app must not be able to read the server credentials.
public struct SourceCredentials: Codable, Equatable, Sendable {
    public var username: String?
    public var password: String?
    /// The access token of a source that signs in with one (Jellyfin, Plex).
    public var serverToken: String?

    public init(username: String? = nil, password: String? = nil, serverToken: String? = nil) {
        self.username = username
        self.password = password
        self.serverToken = serverToken
    }

    public var isEmpty: Bool {
        (username?.isEmpty ?? true) && (password?.isEmpty ?? true) && (serverToken?.isEmpty ?? true)
    }
}

/// The Keychain-backed store for source secrets.
public enum CredentialStore {
    private static let service = "com.rushabh.cartvv.source-credentials"

    /// Stores the secrets of a source, replacing whatever was there.
    ///
    /// Returns `false` when the Keychain refused the write, so the caller can
    /// tell the user instead of silently losing the credentials on the next start.
    @discardableResult
    public static func save(_ credentials: SourceCredentials?, for sourceID: UUID) -> Bool {
        let account = sourceID.uuidString
        guard let credentials, !credentials.isEmpty else {
            delete(for: sourceID)
            return true
        }
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        // After first unlock, so a stream can still start from a background
        // refresh that happens before the user unlocks the device again.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("DRIVEPLAY Keychain write failed: %d", status)
        }
        return status == errSecSuccess
    }

    /// The secrets of a source, if any are stored.
    public static func load(for sourceID: UUID) -> SourceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SourceCredentials.self, from: data)
    }

    /// Removes the secrets of a source.
    public static func delete(for sourceID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Takes the secrets out of a URL that is written to disk, and puts them back
/// when the URL is read again.
///
/// The app builds three kinds of URL that carry a secret: the user info
/// (`http://user:pass@host`), a path segment (Xtream: `/live/<user>/<pass>/<id>`)
/// and a query value (Jellyfin: `?api_key=<token>`).
public enum CredentialRedactor {
    static let userPlaceholder = "__dp_user__"
    static let passPlaceholder = "__dp_pass__"
    static let tokenPlaceholder = "__dp_token__"

    /// Percent-encodes a credential for use in a URL.
    ///
    /// RFC 3986 unreserved set. `&`, `#`, `?` and `/` are structural in a path
    /// or a query, so an unencoded password truncates the request.
    public static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The URL without its secrets.
    public static func redact(_ url: URL, credentials: SourceCredentials?) -> URL {
        guard let credentials, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var changed = false

        if let secret = credentials.username, components.user == secret {
            components.user = userPlaceholder
            changed = true
        }
        if let secret = credentials.password, components.password == secret {
            components.password = passPlaceholder
            changed = true
        }

        var segments = pathSegments(of: components)
        var pathChanged = false
        for index in segments.indices {
            let decoded = segments[index].removingPercentEncoding ?? segments[index]
            if let secret = credentials.username, decoded == secret {
                segments[index] = userPlaceholder
                pathChanged = true
            } else if let secret = credentials.password, decoded == secret {
                segments[index] = passPlaceholder
                pathChanged = true
            }
        }
        if pathChanged {
            components.percentEncodedPath = segments.joined(separator: "/")
            changed = true
        }

        if let items = components.queryItems {
            var newItems = items
            var queryChanged = false
            for index in newItems.indices {
                guard let value = newItems[index].value else { continue }
                if let secret = credentials.serverToken, value == secret {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: tokenPlaceholder)
                    queryChanged = true
                } else if let secret = credentials.username, value == secret {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: userPlaceholder)
                    queryChanged = true
                } else if let secret = credentials.password, value == secret {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: passPlaceholder)
                    queryChanged = true
                }
            }
            if queryChanged {
                components.queryItems = newItems
                changed = true
            }
        }

        return changed ? (components.url ?? url) : url
    }

    /// A URL that is safe to **write into a log**.
    ///
    /// The device's log is readable by anything attached to the phone — an
    /// Xcode console, `idevicesyslog`, a sysdiagnose — so the parts of a URL
    /// that carry a secret are dropped: the user info, the query, and every
    /// path segment but the last (Xtream keeps the user and the password
    /// there). What is left is the host and the name of the file, which is
    /// what says *which* stream failed.
    public static func safeForLog(_ url: URL) -> String {
        guard let host = url.host else { return "<no host>" }
        let scheme = url.scheme ?? "https"
        let name = url.lastPathComponent
        return name.isEmpty ? "\(scheme)://\(host)" : "\(scheme)://\(host)/\(name)"
    }

    /// A URL **string** that is safe to write into a log.
    ///
    /// A string that is not a URL at all is not written out either: it may
    /// still be a password the user pasted.
    public static func safeForLog(_ string: String) -> String {
        guard let url = URL(string: string), url.host != nil else { return "<not a URL>" }
        return safeForLog(url)
    }

    /// The URL with its secrets put back in.
    public static func restore(_ url: URL, credentials: SourceCredentials?) -> URL {
        guard let credentials, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var changed = false

        if components.user == userPlaceholder, let secret = credentials.username {
            components.user = secret
            changed = true
        }
        if components.password == passPlaceholder, let secret = credentials.password {
            components.password = secret
            changed = true
        }

        var segments = pathSegments(of: components)
        var pathChanged = false
        for index in segments.indices {
            if segments[index] == userPlaceholder, let secret = credentials.username {
                segments[index] = percentEncode(secret)
                pathChanged = true
            } else if segments[index] == passPlaceholder, let secret = credentials.password {
                segments[index] = percentEncode(secret)
                pathChanged = true
            }
        }
        if pathChanged {
            components.percentEncodedPath = segments.joined(separator: "/")
            changed = true
        }

        if let items = components.queryItems {
            var newItems = items
            var queryChanged = false
            for index in newItems.indices {
                guard let value = newItems[index].value else { continue }
                if value == tokenPlaceholder, let secret = credentials.serverToken {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: secret)
                    queryChanged = true
                } else if value == userPlaceholder, let secret = credentials.username {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: secret)
                    queryChanged = true
                } else if value == passPlaceholder, let secret = credentials.password {
                    newItems[index] = URLQueryItem(name: newItems[index].name, value: secret)
                    queryChanged = true
                }
            }
            if queryChanged {
                components.queryItems = newItems
                changed = true
            }
        }

        return changed ? (components.url ?? url) : url
    }

    private static func pathSegments(of components: URLComponents) -> [String] {
        components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
