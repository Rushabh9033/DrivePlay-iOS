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

    // MARK: - Decoding

    /// Decoding that tolerates what another build wrote.
    ///
    /// Every key but the name and the address has a default, so a library
    /// written by an older or a newer build still loads. Those two are still
    /// required — a channel without an address is not a channel.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decode(String.self, forKey: .name),
            streamURL: try container.decode(URL.self, forKey: .streamURL),
            groupTitle: try container.decodeIfPresent(String.self, forKey: .groupTitle) ?? "Other",
            logoURL: try container.decodeIfPresent(URL.self, forKey: .logoURL),
            tvgId: try container.decodeIfPresent(String.self, forKey: .tvgId),
            sourceId: try container.decodeIfPresent(UUID.self, forKey: .sourceId) ?? UUID(),
            isFavorite: try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false,
            isPlayable: try container.decodeIfPresent(Bool.self, forKey: .isPlayable) ?? true,
            resolutionLabel: try container.decodeIfPresent(String.self, forKey: .resolutionLabel) ?? "HD",
            lastPlayedPosition: try container.decodeIfPresent(Double.self, forKey: .lastPlayedPosition) ?? 0,
            duration: try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0,
            lastCheckedAt: try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        )
    }

    /// Decodes a library, dropping the entries that cannot be read.
    ///
    /// The library is the one thing the user cannot get back: a single broken
    /// entry must not empty the whole file — and the next save would then
    /// overwrite it with nothing.
    public static func decodeList(from data: Data) -> [Channel] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let decoder = JSONDecoder()
        return entries.compactMap { entry in
            guard let entryData = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(Channel.self, from: entryData)
        }
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
