import Foundation

public struct XtreamClient: Sendable {
    public init() {}
    
    public struct UserAuthInfo: Codable, Sendable {
        public let status: String
        public let expDate: String?
        public let activeCons: String?
        public let maxCons: String?
        
        enum CodingKeys: String, CodingKey {
            case status
            case expDate = "exp_date"
            case activeCons = "active_cons"
            case maxCons = "max_connections"
        }
    }
    
    public struct XtreamCategory: Codable, Sendable {
        public let categoryId: String
        public let categoryName: String
        
        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case categoryName = "category_name"
        }
    }
    
    public struct XtreamStream: Codable, Sendable {
        public let streamId: Int
        public let name: String
        public let streamIcon: String?
        public let categoryId: String?
        public let streamType: String?
        
        enum CodingKeys: String, CodingKey {
            case streamId = "stream_id"
            case name
            case streamIcon = "stream_icon"
            case categoryId = "category_id"
            case streamType = "stream_type"
        }
    }
    
    /// RFC 3986 unreserved set. Credentials are interpolated into query strings and
    /// URL paths, where `&`, `#`, `?` and `/` are structural — an unencoded password
    /// like `p@ss&x` silently truncates the request.
    static func encodeCredential(_ value: String) -> String {
        CredentialRedactor.percentEncode(value)
    }

    public func fetchChannels(
        serverUrl: String,
        username: String,
        password: String,
        sourceId: UUID
    ) async throws -> [Channel] {
        let base = URLPolicy.normalized(serverUrl)

        let encodedUser = Self.encodeCredential(username)
        let encodedPass = Self.encodeCredential(password)

        // 1. Fetch categories
        let categoriesUrl = "\(base)/player_api.php?username=\(encodedUser)&password=\(encodedPass)&action=get_live_categories"
        guard let catUrl = URL(string: categoriesUrl) else {
            throw URLError(.badURL)
        }

        var categoryMap: [String: String] = [:]
        if let (catData, _) = try? await URLSession.shared.data(from: catUrl) {
            if let categories = try? JSONDecoder().decode([XtreamCategory].self, from: catData) {
                for c in categories {
                    categoryMap[c.categoryId] = c.categoryName
                }
            }
        }

        // 2. Fetch live streams
        let streamsUrl = "\(base)/player_api.php?username=\(encodedUser)&password=\(encodedPass)&action=get_live_streams"
        guard let sUrl = URL(string: streamsUrl) else {
            throw URLError(.badURL)
        }

        let (streamsData, _) = try await URLSession.shared.data(from: sUrl)
        let streams = try JSONDecoder().decode([XtreamStream].self, from: streamsData)

        return streams.compactMap { stream in
            // A stream can belong to several categories; Xtream reports them as "1,2".
            let group = stream.categoryId?
                .split(separator: ",")
                .compactMap { categoryMap[String($0)] }
                .first ?? "Live TV"
            let streamEndpoint = "\(base)/live/\(encodedUser)/\(encodedPass)/\(stream.streamId).m3u8"
            // Falling back to the API endpoint here would hand the player a JSON
            // document to "play", so drop the channel instead.
            guard let streamURL = URL(string: streamEndpoint) else { return nil }
            let iconURL = stream.streamIcon.flatMap { URL(string: $0) }

            return Channel(
                id: UUID(),
                name: stream.name,
                streamURL: streamURL,
                groupTitle: group,
                logoURL: iconURL,
                tvgId: "\(stream.streamId)",
                sourceId: sourceId,
                isFavorite: false,
                isPlayable: true,
                resolutionLabel: "1080P"
            )
        }
    }
}
