import Foundation

public struct Channel: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var streamURL: URL
    public var groupTitle: String
    public var logoURL: URL?
    public var tvgId: String?
    public var sourceId: UUID
    public var isFavorite: Bool
    public var isPlayable: Bool
    public var resolutionLabel: String
    public var lastPlayedPosition: Double
    public var duration: Double
    public var lastCheckedAt: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        streamURL: URL,
        groupTitle: String = "Other",
        logoURL: URL? = nil,
        tvgId: String? = nil,
        sourceId: UUID = UUID(),
        isFavorite: Bool = false,
        isPlayable: Bool = true,
        resolutionLabel: String = "HD",
        lastPlayedPosition: Double = 0,
        duration: Double = 0,
        lastCheckedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.groupTitle = groupTitle.isEmpty ? "Other" : groupTitle
        self.logoURL = logoURL
        self.tvgId = tvgId
        self.sourceId = sourceId
        self.isFavorite = isFavorite
        self.isPlayable = isPlayable
        self.resolutionLabel = resolutionLabel
        self.lastPlayedPosition = lastPlayedPosition
        self.duration = duration
        self.lastCheckedAt = lastCheckedAt
    }
}

public struct ChannelGroup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public var channels: [Channel]
    
    public init(name: String, channels: [Channel]) {
        self.name = name
        self.channels = channels
    }
}
