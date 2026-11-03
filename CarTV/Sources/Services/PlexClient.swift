import Foundation

public struct PlexClient: Sendable {
    public init() {}
    
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
    
    public struct PlexResource: Codable, Sendable {
        public let name: String
        public let clientIdentifier: String
        public let provides: String
        public let connections: [PlexConnection]?
        
        public struct PlexConnection: Codable, Sendable {
            public let uri: String
            public let local: Bool
        }
    }
    
    private let clientIdentifier = "CarTV-iOS-Player"
    
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
        guard let url = URL(string: "https://plex.tv/api/v2/resources?includeHttps=1") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONDecoder().decode([PlexResource].self, from: data)) ?? []
    }
}
