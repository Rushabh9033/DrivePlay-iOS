import Foundation

public struct JellyfinClient: Sendable {
    public init() {}
    
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
        enum CodingKeys: String, CodingKey {
            case items = "Items"
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
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(AuthResponse.self, from: data)
        return (resp.accessToken, resp.user.id)
    }
    
    public func fetchLibraryChannels(serverUrl: String, token: String, userId: String, sourceId: UUID) async throws -> [Channel] {
        let base = URLPolicy.normalized(serverUrl)
        guard let url = URL(string: "\(base)/Users/\(userId)/Items?IncludeItemTypes=Movie,Episode&Recursive=true&Limit=100") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(ItemsResponse.self, from: data)
        
        return resp.items.compactMap { item in
            let streamEndpoint = "\(base)/Videos/\(item.id)/stream.mp4?static=true&api_key=\(token)"
            guard let streamURL = URL(string: streamEndpoint) else { return nil }
            let artworkEndpoint = "\(base)/Items/\(item.id)/Images/Primary?fillWidth=400&quality=90"
            
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
