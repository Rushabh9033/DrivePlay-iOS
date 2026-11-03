import Foundation

public struct WatchedItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let channelId: UUID
    public let sourceId: UUID
    public let name: String
    public var streamURL: URL
    public let groupTitle: String
    public let logoURL: URL?
    public let resolutionLabel: String
    public let watchedAt: Date
    
    public init(
        id: UUID = UUID(),
        channelId: UUID,
        sourceId: UUID,
        name: String,
        streamURL: URL,
        groupTitle: String,
        logoURL: URL? = nil,
        resolutionLabel: String = "HD",
        watchedAt: Date = Date()
    ) {
        self.id = id
        self.channelId = channelId
        self.sourceId = sourceId
        self.name = name
        self.streamURL = streamURL
        self.groupTitle = groupTitle
        self.logoURL = logoURL
        self.resolutionLabel = resolutionLabel
        self.watchedAt = watchedAt
    }
}

@MainActor
public final class WatchHistoryStore: ObservableObject {
    public static let shared = WatchHistoryStore()
    
    @Published public private(set) var history: [WatchedItem] = []
    private let storageKey = "cartv_playlist_watch_history"
    
    public init() {
        load()
    }
    
    public func recordWatch(_ channel: Channel) {
        // Remove existing entry for the same channel to bring it to the top
        history.removeAll { $0.channelId == channel.id }
        
        let item = WatchedItem(
            channelId: channel.id,
            sourceId: channel.sourceId,
            name: channel.name,
            // The stored URL holds no credentials: they live in the Keychain.
            streamURL: CredentialRedactor.redact(
                channel.streamURL,
                credentials: PlaylistStore.shared.credentials(for: channel.sourceId)
            ),
            groupTitle: channel.groupTitle,
            logoURL: channel.logoURL,
            resolutionLabel: channel.resolutionLabel,
            watchedAt: Date()
        )
        
        history.insert(item, at: 0)
        
        // Keep last 100 items
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        
        save()
    }
    
    public func history(for sourceId: UUID) -> [WatchedItem] {
        history.filter { $0.sourceId == sourceId }
    }
    
    public func clearHistory(for sourceId: UUID) {
        history.removeAll { $0.sourceId == sourceId }
        save()
    }
    
    private func save() {
        let items = history
        let key = storageKey
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           var items = try? JSONDecoder().decode([WatchedItem].self, from: data) {
            // The stored URLs hold no credentials: put them back for playback.
            for index in items.indices {
                items[index].streamURL = CredentialRedactor.restore(
                    items[index].streamURL,
                    credentials: PlaylistStore.shared.credentials(for: items[index].sourceId)
                )
            }
            self.history = items
        }
    }
}
