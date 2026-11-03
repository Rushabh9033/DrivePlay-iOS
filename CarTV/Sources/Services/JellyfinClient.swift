import Foundation

public struct JellyfinClient: Sendable {
    /// The session the client talks to the server with. A test hands in one
    /// with its own protocol, so a whole library can be served without a
    /// server.
    private nonisolated(unsafe) let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public struct AuthResponse: Codable, Sendable {
        public let accessToken: String
        public let user: UserInfo
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "AccessToken"
            case user = "User"
        }
        
        public struct UserInfo: Codable, Sendable {
            public let id: String
            public let name: String
            
            enum CodingKeys: String, CodingKey {
                case id = "Id"
                case name = "Name"
            }
        }
    }
    
    public struct MediaItem: Codable, Sendable {
        public let id: String
        public let name: String
        public let type: String
        public let mediaType: String?
        public let runTimeTicks: Int64?
        
        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case type = "Type"
            case mediaType = "MediaType"
            case runTimeTicks = "RunTimeTicks"
        }
    }
    
    public struct ItemsResponse: Codable, Sendable {
        public let items: [MediaItem]
        /// The number of items the server has in total. The paging loop needs
        /// it to know when it has seen everything.
        public let totalRecordCount: Int
        enum CodingKeys: String, CodingKey {
            case items = "Items"
            case totalRecordCount = "TotalRecordCount"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.items = try container.decodeIfPresent([MediaItem].self, forKey: .items) ?? []
            self.totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount) ?? 0
        }
    }
    
    public func authenticate(serverUrl: String, username: String, password: String) async throws -> (token: String, userId: String) {
        let base = URLPolicy.normalized(serverUrl)
        guard let url = URL(string: "\(base)/Users/AuthenticateByName") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MediaBrowser Client=\"CarTV\", Device=\"iOS\", DeviceId=\"CarTV-01\", Version=\"1.2.0\"", forHTTPHeaderField: "X-Emby-Authorization")
        
        let body: [String: String] = ["Username": username, "Pw": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        let resp = try JSONDecoder().decode(AuthResponse.self, from: data)
        return (resp.accessToken, resp.user.id)
    }
    
    /// How many items one page asks for. The server caps this anyway.
    private static let pageSize = 200

    /// The whole library, page by page.
    ///
    /// A single request with `Limit=100` silently truncated the library: the
    /// user saw the first hundred items and nothing else, with no hint that
    /// more existed. The server tells the total, so the pages are walked until
    /// they are all read.
    public func fetchLibraryChannels(serverUrl: String, token: String, userId: String, sourceId: UUID) async throws -> [Channel] {
        let base = URLPolicy.normalized(serverUrl)
        var items: [MediaItem] = []
        var startIndex = 0
        var total = 0

        // A server that keeps reporting a full page forever would loop for
        // ever; the guard below stops the loop, this caps it.
        while startIndex < 10_000 {
            guard let url = URL(string: "\(base)/Users/\(userId)/Items?IncludeItemTypes=Movie,Episode&Recursive=true&Limit=\(Self.pageSize)&StartIndex=\(startIndex)") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")

            let (data, _) = try await session.data(for: request)
            let resp = try JSONDecoder().decode(ItemsResponse.self, from: data)

            items.append(contentsOf: resp.items)
            total = resp.totalRecordCount
            // A short page means the end, whatever the total says.
            guard resp.items.count >= Self.pageSize else { break }
            startIndex += resp.items.count
        }

        if total > 0 && items.count < total {
            NSLog("DRIVEPLAY jellyfin: read %d of %d items", items.count, total)
        }

        return items.compactMap { item in
            let streamEndpoint = "\(base)/Videos/\(item.id)/stream.mp4?static=true&api_key=\(token)"
            guard let streamURL = URL(string: streamEndpoint) else { return nil }
            // The artwork URL is loaded by the image loader, which cannot send
            // the token header — so the token has to be in the query.
            let artworkEndpoint = "\(base)/Items/\(item.id)/Images/Primary?fillWidth=400&quality=90&api_key=\(token)"

            return Channel(
                id: UUID(),
                name: item.name,
                streamURL: streamURL,
                groupTitle: item.type == "Movie" ? "Movies" : "TV Series",
                logoURL: URL(string: artworkEndpoint),
                tvgId: item.id,
                sourceId: sourceId,
                isFavorite: false,
                isPlayable: true,
                resolutionLabel: "1080P"
            )
        }
    }
}
