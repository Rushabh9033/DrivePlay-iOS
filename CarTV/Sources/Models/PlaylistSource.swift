import Foundation

public enum SourceType: String, Codable, CaseIterable, Sendable {
    case m3u = "M3U Playlist"
    case xtream = "Xtream Codes"
    case jellyfin = "Jellyfin"
    case emby = "Emby"
    case plex = "Plex"
    case local = "Local Files"
    
    public var iconName: String {
        switch self {
        case .m3u: return "list.bullet.rectangle"
        case .xtream: return "antenna.radiowaves.left.and.right"
        case .jellyfin: return "server.rack"
        case .emby: return "server.rack"
        case .plex: return "play.tv"
        case .local: return "folder.fill"
        }
    }
}

public struct PlaylistSource: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: SourceType
    public var urlString: String
    public var username: String?
    public var password: String?
    public var serverToken: String?
    public var lastUpdated: Date
    public var channelCount: Int
    public var isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: SourceType,
        urlString: String,
        username: String? = nil,
        password: String? = nil,
        serverToken: String? = nil,
        lastUpdated: Date = Date(),
        channelCount: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.urlString = urlString
        self.username = username
        self.password = password
        self.serverToken = serverToken
        self.lastUpdated = lastUpdated
        self.channelCount = channelCount
        self.isEnabled = isEnabled
    }

    // The secrets never reach the encoded form: they live in the Keychain, see
    // `CredentialStore`. They are still *decoded*, so a source saved by an
    // older build (which kept them in the plist) can be migrated.
    enum CodingKeys: String, CodingKey {
        case id, name, type, urlString, username, password, serverToken, lastUpdated, channelCount, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(SourceType.self, forKey: .type)
        self.urlString = try container.decode(String.self, forKey: .urlString)
        self.username = try container.decodeIfPresent(String.self, forKey: .username)
        self.password = try container.decodeIfPresent(String.self, forKey: .password)
        self.serverToken = try container.decodeIfPresent(String.self, forKey: .serverToken)
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        self.channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 0
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(channelCount, forKey: .channelCount)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

public struct LocalVideoItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var relativePath: String
    public var fileSize: Int64
    public var duration: Double
    public var dateAdded: Date
    public var resolution: String
    public var isAudioOnly: Bool
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: dateAdded)
    }
    
    public var formatBadge: String {
        let ext = (relativePath as NSString).pathExtension.uppercased()
        return ext.isEmpty ? (isAudioOnly ? "AUDIO" : "VIDEO") : ext
    }
    
    public var formattedDuration: String {
        guard duration > 0 else { return "--:--" }
        let total = Int(duration)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        relativePath: String,
        fileSize: Int64,
        duration: Double = 0,
        dateAdded: Date = Date(),
        resolution: String = "1080P",
        isAudioOnly: Bool = false
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.duration = duration
        self.dateAdded = dateAdded
        self.resolution = resolution
        self.isAudioOnly = isAudioOnly
    }
    
    // Custom decoding for backwards compatibility with existing saved items
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.fileSize = try container.decode(Int64.self, forKey: .fileSize)
        self.duration = try container.decode(Double.self, forKey: .duration)
        self.dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        self.resolution = try container.decodeIfPresent(String.self, forKey: .resolution) ?? "1080P"
        let ext = (relativePath as NSString).pathExtension.lowercased()
        let audioExts = ["mp3", "m4a", "flac", "wav", "aac", "aiff"]
        self.isAudioOnly = try container.decodeIfPresent(Bool.self, forKey: .isAudioOnly) ?? audioExts.contains(ext)
    }
}
