import Foundation

public struct PlexClient: Sendable {
    public init() {}

    /// What went wrong while talking to plex.tv.
    ///
    /// Every one of these used to arrive as the same message — *"No Plex
    /// media server found on this account"* — which is a **lie**: an account
    /// that was refused and an account that has no server are two different
    /// problems with two different answers.
    public enum PlexError: LocalizedError {
        /// plex.tv refused the request — the account link was not accepted.
        case refused(status: Int)
        /// plex.tv answered with something the app cannot read.
        case unreadableAnswer
        /// The account is fine, but it has no media server on it.
        case noMediaServer

        public var errorDescription: String? {
            switch self {
            case .refused(let status):
                return "plex.tv refused the account (HTTP \(status)). The link was not accepted — sign in again at plex.tv/link."
            case .unreadableAnswer:
                return "plex.tv's answer could not be read."
            case .noMediaServer:
                return "This account has no media server. Add one in the Plex app, then check again."
            }
        }
    }

    public struct PlexPin: Codable, Sendable {
        public let id: Int
        public let code: String
        public let authToken: String?
        /// Plex returns the lifetime as `expiresIn` (seconds) plus a `createdAt`
        /// timestamp. There is no `expiresAt` key — decoding one as required made
        /// every pin response fail with `keyNotFound` and broke Plex sign-in.
        public let expiresIn: Int?
        public let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case code
            case authToken
            case expiresIn
            case createdAt
        }
    }
    
    /// A device that is signed in to an account.
    ///
    /// Every value has a default: **one odd device must not empty the whole
    /// list**. A resource that leaves a field out is a device the account does
    /// not use — it is not a reason to answer *"this account has no media
    /// server"*.
    public struct PlexResource: Codable, Sendable {
        public let name: String
        public let clientIdentifier: String
        public let provides: String
        public let connections: [PlexConnection]?

        public struct PlexConnection: Codable, Sendable {
            public let uri: String
            public let local: Bool
            /// The port the server answers on (32400 for a media server).
            public let port: Int?

            enum CodingKeys: String, CodingKey {
                case uri
                case local
                case port
            }

            public init(uri: String, local: Bool, port: Int? = nil) {
                self.uri = uri
                self.local = local
                self.port = port
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
                self.local = try container.decodeIfPresent(Bool.self, forKey: .local) ?? false
                self.port = try container.decodeIfPresent(Int.self, forKey: .port)
            }
        }

        enum CodingKeys: String, CodingKey {
            case name
            case clientIdentifier
            case provides
            case connections
        }

        public init(name: String,
                    clientIdentifier: String,
                    provides: String,
                    connections: [PlexConnection]?) {
            self.name = name
            self.clientIdentifier = clientIdentifier
            self.provides = provides
            self.connections = connections
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            self.clientIdentifier = try container.decodeIfPresent(String.self, forKey: .clientIdentifier) ?? ""
            self.provides = Self.decodeProvides(from: container)
            self.connections = try container.decodeIfPresent([PlexConnection].self, forKey: .connections)
        }

        /// What the device provides: a server, a player, a client.
        ///
        /// plex.tv has answered this both as a string (`"server"`) and as a
        /// list (`["server"]`); a decoder that only knows one of them reads
        /// **nothing** and the server looks like it is not there.
        private static func decodeProvides(
            from container: KeyedDecodingContainer<CodingKeys>
        ) -> String {
            if let text = try? container.decodeIfPresent(String.self, forKey: .provides) {
                return text
            }
            if let list = try? container.decodeIfPresent([String].self, forKey: .provides) {
                return list.joined(separator: ",")
            }
            return ""
        }
    }
    
    /// A section of a Plex library: a folder of movies or of shows.
    ///
    /// Every value has a default: a server that leaves one out must not empty
    /// the whole library.
    public struct PlexSection: Codable, Sendable {
        public let key: String
        public let title: String
        public let type: String?

        enum CodingKeys: String, CodingKey {
            case key
            case title
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.type = try container.decodeIfPresent(String.self, forKey: .type)
        }
    }

    /// One item of a Plex library section.
    public struct PlexLibraryItem: Codable, Sendable {
        public let title: String
        public let ratingKey: String?
        public let type: String?
        public let thumb: String?
        public let media: [PlexMedia]?

        enum CodingKeys: String, CodingKey {
            case title
            case ratingKey
            case type
            case thumb
            case media = "Media"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
            self.ratingKey = try container.decodeIfPresent(String.self, forKey: .ratingKey)
            self.type = try container.decodeIfPresent(String.self, forKey: .type)
            self.thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
            self.media = try? container.decodeIfPresent([PlexMedia].self, forKey: .media)
        }

        /// The path of the file of the item: the first part of its first media.
        public var firstPartKey: String? {
            for media in media ?? [] {
                if let key = media.part?.first?.key, !key.isEmpty { return key }
            }
            return nil
        }
    }

    /// The files an item is stored in.
    public struct PlexMedia: Codable, Sendable {
        public let part: [PlexPart]?

        enum CodingKeys: String, CodingKey {
            case part = "Part"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.part = try? container.decodeIfPresent([PlexPart].self, forKey: .part)
        }
    }

    /// One file of an item.
    public struct PlexPart: Codable, Sendable {
        public let key: String?
        public let container: String?

        enum CodingKeys: String, CodingKey {
            case key
            case container
        }
    }

    /// The `MediaContainer` Plex wraps every list in.
    ///
    /// A list is either a `Directory` (the sections of a library) or a
    /// `Metadata` (the items of a section).
    private struct PlexList<T: Decodable>: Decodable {
        let directory: [T]?
        let metadata: [T]?

        enum CodingKeys: String, CodingKey {
            case directory = "Directory"
            case metadata = "Metadata"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.directory = try? container.decodeIfPresent([T].self, forKey: .directory)
            self.metadata = try? container.decodeIfPresent([T].self, forKey: .metadata)
        }
    }

    /// The envelope of a Plex answer.
    private struct PlexResponse<T: Decodable>: Decodable {
        let mediaContainer: PlexList<T>

        enum CodingKeys: String, CodingKey {
            case mediaContainer = "MediaContainer"
        }
    }

    private let clientIdentifier = "CarTV-iOS-Player"

    /// Where the servers of an account are asked for.
    ///
    /// `includeRelay=1` is not optional: it is what puts the `*.plex.direct`
    /// address of a server into the answer. Without it a phone that is not on
    /// the server's own network sees a server with **no usable address at
    /// all**, and the account looks like it has no server.
    public static let resourcesURL =
        "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1"

    public func createPin() async throws -> PlexPin {
        // Omitting strong=true returns the official 4-character code (e.g. "RN9H") for plex.tv/link
        guard let url = URL(string: "https://plex.tv/api/v2/pins") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue("CarTV", forHTTPHeaderField: "X-Plex-Product")
        
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }
    
    public func checkPin(pinId: Int) async throws -> String? {
        guard let url = URL(string: "https://plex.tv/api/v2/pins/\(pinId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let pin = try JSONDecoder().decode(PlexPin.self, from: data)
        return pin.authToken
    }
    
    public func fetchServers(authToken: String) async throws -> [PlexResource] {
        // `includeRelay=1` is what puts the `*.plex.direct` address of a
        // server into the answer: without it a phone that is not on the
        // server's own network sees a server with no usable address at all.
        guard let url = URL(string: Self.resourcesURL) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")

        let (data, response) = try await URLSession.shared.data(for: req)
        // The status says what went wrong. An account that was not accepted
        // answers 401 with a JSON **object**, and decoding that as a list of
        // resources fails — so the status has to be read before the body,
        // and a failed decode must not be swallowed into "no servers".
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlexError.refused(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode([PlexResource].self, from: data)
        } catch {
            throw PlexError.unreadableAnswer
        }
    }

    /// The media server of an account: its name and the address it answers on.
    ///
    /// plex.tv is the cloud API, not the server — the account's own server has
    /// to be found before a source can point at it. The address on the local
    /// network is preferred: a remote address cannot reach a file that is not
    /// on the public internet.
    public func preferredServer(authToken: String) async throws -> (name: String, address: String)? {
        let servers = try await fetchServers(authToken: authToken)
        return Self.preferredServer(in: servers)
    }

    /// The media server of an account, out of the resources plex.tv reported.
    ///
    /// The local address wins: a remote address cannot reach a file that is
    /// not on the public internet. The rule holds **across** the servers too —
    /// one server's remote address must not beat another server's local one.
    public static func preferredServer(in servers: [PlexResource]) -> (name: String, address: String)? {
        let mediaServers = servers.filter { $0.provides.contains("server") }
        // A resource that does not say what it provides is a candidate only
        // when it answers on a port — that is what a media server does. A
        // resource that says it is a **player** is never the server, whatever
        // it answers on: falling back to *every* resource would let the
        // account's own phone pass for the server.
        let candidates = mediaServers.isEmpty
            ? servers.filter { resource in
                resource.provides.isEmpty
                    && (resource.connections ?? []).contains { $0.port != nil && !$0.uri.isEmpty }
            }
            : mediaServers
        // A server that answers on the local network comes first; the order
        // plex.tv sent is kept among the rest.
        let ordered = candidates.filter { hasLocalAddress($0) }
            + candidates.filter { !hasLocalAddress($0) }
        for server in ordered {
            guard let uri = preferredAddress(of: server) else { continue }
            let name = server.name.isEmpty ? "Plex Server" : server.name
            return (name, URLPolicy.normalized(uri))
        }
        return nil
    }

    /// The library of a Plex media server, as channels.
    ///
    /// The items are grouped by the section they sit in: a folder of the
    /// server's library is what a channel list is.
    public func fetchLibraryChannels(serverUrl: String, token: String, sourceId: UUID) async throws -> [Channel] {
        let base = URLPolicy.normalized(serverUrl)
        let sections = try await fetchSections(base: base, token: token)

        var channels: [Channel] = []
        for section in sections {
            guard !section.key.isEmpty else { continue }
            // One unreadable section must not cost the user the whole library.
            let items = (try? await fetchItems(base: base, key: section.key, token: token)) ?? []
            for item in items {
                guard let partKey = item.firstPartKey else { continue }
                // The player cannot send headers, so the token rides in the URL.
                let streamURL = URL(string: "\(base)\(partKey)?X-Plex-Token=\(CredentialRedactor.percentEncode(token))")
                guard let streamURL else { continue }
                let artwork = item.thumb.flatMap { URL(string: "\(base)\($0)/163840") }

                channels.append(Channel(
                    name: item.title,
                    streamURL: streamURL,
                    groupTitle: section.title,
                    logoURL: artwork,
                    tvgId: item.ratingKey,
                    sourceId: sourceId,
                    isFavorite: false,
                    isPlayable: true,
                    resolutionLabel: "1080P"
                ))
            }
        }
        return channels
    }

    /// The sections (the folders) of the library of a server.
    private func fetchSections(base: String, token: String) async throws -> [PlexSection] {
        guard let url = URL(string: "\(base)/library/sections") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(for: serverRequest(url: url, token: token))
        return Self.decodeList(PlexSection.self, from: data)
    }

    /// The items of one section of the library of a server.
    private func fetchItems(base: String, key: String, token: String) async throws -> [PlexLibraryItem] {
        guard let url = URL(string: "\(base)/library/sections/\(key)/all") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(for: serverRequest(url: url, token: token))
        return Self.decodeList(PlexLibraryItem.self, from: data)
    }

    /// The address a server answers on: the local one when it has one.
    private static func preferredAddress(of server: PlexResource) -> String? {
        let usable = (server.connections ?? []).filter { !$0.uri.isEmpty }
        return (usable.first(where: { $0.local }) ?? usable.first)?.uri
    }

    /// True when the server can be reached on the local network.
    private static func hasLocalAddress(_ server: PlexResource) -> Bool {
        (server.connections ?? []).contains { $0.local && !$0.uri.isEmpty }
    }

    /// A request to a media server, with the token of the account.
    private func serverRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    /// Decodes a list of Plex objects, wrapped in a `MediaContainer` or sent
    /// as a bare array.
    private static func decodeList<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(PlexResponse<T>.self, from: data) {
            if let list = response.mediaContainer.directory, !list.isEmpty { return list }
            if let list = response.mediaContainer.metadata, !list.isEmpty { return list }
        }
        return (try? decoder.decode([T].self, from: data)) ?? []
    }
}
