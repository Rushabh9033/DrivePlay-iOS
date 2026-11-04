import Foundation

@MainActor
public final class PlaylistStore: ObservableObject {
    public static let shared = PlaylistStore()
    
    @Published public var sources: [PlaylistSource] = []
    @Published public var channels: [Channel] = []
    @Published public var selectedGroup: String = "All"
    @Published public var searchQuery: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    
    private let m3uParser = M3UParser()
    private let xtreamClient = XtreamClient()
    /// The `UserDefaults` key the sources are saved under.
    public static let sourcesStorageKey = "cartv_saved_sources"
    private let channelsStorageKey = "cartv_saved_channels"
    
    // Pre-indexed high-performance memory caches (O(1) lookups)
    private var cachedChannelsBySource: [UUID: [Channel]] = [:]
    private var cachedGroupsBySource: [UUID: [ChannelGroup]] = [:]
    private var cachedGlobalGroups: [ChannelGroup] = []
    
    public func rebuildIndex() {
        let sourceGrouped = Dictionary(grouping: channels, by: { $0.sourceId })
        var newGroupsBySource: [UUID: [ChannelGroup]] = [:]
        
        for (sourceId, sourceChs) in sourceGrouped {
            let grpDict = Dictionary(grouping: sourceChs, by: { $0.groupTitle })
            let grpList = grpDict.map { ChannelGroup(name: $0.key, channels: $0.value) }
                .sorted { sortOrder(for: $0.name) < sortOrder(for: $1.name) }
            newGroupsBySource[sourceId] = grpList
        }
        
        let globalDict = Dictionary(grouping: channels, by: { $0.groupTitle })
        let globalList = globalDict.map { ChannelGroup(name: $0.key, channels: $0.value) }
            .sorted { sortOrder(for: $0.name) < sortOrder(for: $1.name) }
        
        self.cachedChannelsBySource = sourceGrouped
        self.cachedGroupsBySource = newGroupsBySource
        self.cachedGlobalGroups = globalList
    }
    
    private func sortOrder(for name: String) -> Int {
        let order = ["Movies": 0, "Live TV": 1, "Series": 2, "Sports": 3, "News": 4, "Other": 99]
        return order[name] ?? 50
    }
    
    /// The search query without the spaces around it.
    ///
    /// The query is trimmed once, here, and every match is made against the
    /// trimmed value — a trailing space used to hide every result.
    public var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var groups: [ChannelGroup] {
        let q = trimmedSearchQuery
        if q.isEmpty {
            return cachedGlobalGroups
        }
        return cachedGlobalGroups.compactMap { group in
            let filtered = group.channels.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.groupTitle.localizedCaseInsensitiveContains(q)
            }
            return filtered.isEmpty ? nil : ChannelGroup(name: group.name, channels: filtered)
        }
    }
    
    /// Every group, ignoring `searchQuery`.
    ///
    /// `groups` applies the handset search box, which must not shrink the catalogue
    /// shown on a second screen (CarPlay) while the user types on the phone.
    public var allGroups: [ChannelGroup] { cachedGlobalGroups }

    public func channels(for sourceId: UUID) -> [Channel] {
        if let cached = cachedChannelsBySource[sourceId] {
            return cached
        }
        return channels.filter { $0.sourceId == sourceId }
    }
    
    public func groups(for sourceId: UUID) -> [ChannelGroup] {
        if let cached = cachedGroupsBySource[sourceId] {
            return cached
        }
        return []
    }

    /// The channels of the group the given channel belongs to.
    ///
    /// This is the list the player's "next" walks: the channel's **own**
    /// group, in the order the playlist holds it.
    public func channels(inGroupOf channel: Channel) -> [Channel] {
        channels(for: channel.sourceId).filter { $0.groupTitle == channel.groupTitle }
    }
    
    public var favoriteChannels: [Channel] {
        channels.filter { $0.isFavorite }
    }
    
    public init() {
        loadData()
    }
    
    public func toggleFavorite(for channel: Channel) {
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx].isFavorite.toggle()
            saveChannels()
        }
    }
    
    public func addM3USource(name: String, urlString: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid playlist URL."
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                errorMessage = "Failed to decode playlist text."
                return
            }
            
            let source = PlaylistSource(
                name: name.isEmpty ? "M3U Playlist" : name,
                type: .m3u,
                urlString: urlString
            )
            
            let parsed = try m3uParser.parse(content: content, sourceId: source.id)
            sources.append(source)
            channels.append(contentsOf: parsed)
            saveSources()
            saveChannels()
            
            // Probe channels in background
            Task {
                await SourceHealthService.shared.probeChannels(parsed)
            }
        } catch {
            errorMessage = URLPolicy.message(for: error)
        }
    }
    
    public func addXtreamSource(name: String, serverUrl: String, username: String, pass: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let source = PlaylistSource(
            name: name.isEmpty ? "Xtream Server" : name,
            type: .xtream,
            urlString: serverUrl,
            username: username,
            password: pass
        )
        
        do {
            let parsed = try await xtreamClient.fetchChannels(
                serverUrl: serverUrl,
                username: username,
                password: pass,
                sourceId: source.id
            )
            sources.append(source)
            channels.append(contentsOf: parsed)
            saveSources()
            saveChannels()
        } catch {
            errorMessage = URLPolicy.message(for: error)
        }
    }
    
    public func addJellyfinSource(name: String, serverUrl: String, username: String, pass: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let client = JellyfinClient()
        do {
            let auth = try await client.authenticate(serverUrl: serverUrl, username: username, password: pass)
            let source = PlaylistSource(
                name: name.isEmpty ? "Jellyfin Server" : name,
                type: .jellyfin,
                urlString: serverUrl,
                username: username,
                password: pass,
                // The access token ends up in every stream URL, so it has to be
                // kept with the other secrets.
                serverToken: auth.token
            )
            let items = try await client.fetchLibraryChannels(serverUrl: serverUrl, token: auth.token, userId: auth.userId, sourceId: source.id)
            sources.append(source)
            channels.append(contentsOf: items)
            saveSources()
            saveChannels()
        } catch {
            errorMessage = "Server connection failed: \(URLPolicy.message(for: error))"
        }
    }
    
    public func addPlexSource(name: String, serverUrl: String, token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let client = PlexClient()
        do {
            let source = PlaylistSource(
                name: name.isEmpty ? "Plex Server" : name,
                type: .plex,
                urlString: serverUrl,
                // The token ends up in every stream URL, so it has to be kept
                // with the other secrets.
                serverToken: token
            )
            let items = try await client.fetchLibraryChannels(serverUrl: serverUrl, token: token, sourceId: source.id)
            guard !items.isEmpty else {
                errorMessage = "The Plex server has no playable media."
                return
            }
            sources.append(source)
            channels.append(contentsOf: items)
            saveSources()
            saveChannels()
        } catch {
            errorMessage = "Server connection failed: \(URLPolicy.message(for: error))"
        }
    }

    public func removeSource(_ source: PlaylistSource) {
        sources.removeAll { $0.id == source.id }
        channels.removeAll { $0.sourceId == source.id }
        CredentialStore.delete(for: source.id)
        saveSources()
        saveChannels()
    }
    
    // MARK: - Verified Sample / Demo Sources for User Testing
    
    public func addSampleM3USource() {
        let sourceId = UUID()
        let sampleSource = PlaylistSource(
            id: sourceId,
            name: "Sample M3U8 Playlist",
            type: .m3u,
            urlString: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
            channelCount: 6
        )
        
        let sampleChannels: [Channel] = [
            Channel(
                name: "Big Buck Bunny (Feature Film)",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Movies",
                logoURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/320px-Big_buck_bunny_poster_big.jpg"),
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Sintel Cinema (4K Master)",
                streamURL: URL(string: "https://bitmovin-a.akamaihd.net/content/sintel/hls/playlist.m3u8")!,
                groupTitle: "Movies",
                logoURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Sintel_poster.jpg/320px-Sintel_poster.jpg"),
                sourceId: sourceId,
                resolutionLabel: "4K"
            ),
            Channel(
                name: "Tears of Steel (Sci-Fi Film)",
                streamURL: URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!,
                groupTitle: "Movies",
                logoURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Tears_of_Steel_poster.jpg/320px-Tears_of_Steel_poster.jpg"),
                sourceId: sourceId,
                resolutionLabel: "4K"
            ),
            Channel(
                name: "Red Bull TV Live Sports",
                streamURL: URL(string: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8")!,
                groupTitle: "Sports",
                logoURL: URL(string: "https://images.redbull.com/image/upload/app-icon-rb-tv.png"),
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "NASA HD Live Space Stream",
                streamURL: URL(string: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8")!,
                groupTitle: "Live TV",
                logoURL: URL(string: "https://www.nasa.gov/sites/default/files/thumbnails/image/nasa-logo-web-rgb.png"),
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Bloomberg Global Finance Live",
                streamURL: URL(string: "https://liveproduseast.akamaized.net/us/Channel-HD-AWS-virginia-1/master.m3u8")!,
                groupTitle: "Live TV",
                logoURL: URL(string: "https://assets.bwbx.io/s3/javelin/public/hub/images/favicon-black-6320a9a62f.png"),
                sourceId: sourceId,
                resolutionLabel: "HD"
            )
        ]
        
        sources.append(sampleSource)
        channels.append(contentsOf: sampleChannels)
        saveSources()
        saveChannels()
        
        Task.detached(priority: .background) {
            await SourceHealthService.shared.probeChannels(sampleChannels)
        }
    }
    
    public func addSampleXtreamSource() {
        let sourceId = UUID()
        let sampleSource = PlaylistSource(
            id: sourceId,
            name: "Demo Xtream Server",
            type: .xtream,
            urlString: "http://xtream.demo-iptv.net:8080",
            username: "demo_user",
            channelCount: 5
        )
        
        let sampleChannels: [Channel] = [
            Channel(
                name: "Action Cinema VOD (Xtream Movie)",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "World Drama Series (Episode 01)",
                streamURL: URL(string: "https://bitmovin-a.akamaihd.net/content/sintel/hls/playlist.m3u8")!,
                groupTitle: "Series",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "HD"
            ),
            Channel(
                name: "Xtream Sports Premier Live",
                streamURL: URL(string: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8")!,
                groupTitle: "Live TV",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Xtream 24/7 Documentaries",
                streamURL: URL(string: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8")!,
                groupTitle: "Live TV",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "HD"
            ),
            Channel(
                name: "Blockbuster Classics VOD",
                streamURL: URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "4K"
            )
        ]
        
        sources.append(sampleSource)
        channels.append(contentsOf: sampleChannels)
        saveSources()
        saveChannels()
        
        Task.detached(priority: .background) {
            await SourceHealthService.shared.probeChannels(sampleChannels)
        }
    }
    
    public func addSampleJellyfinSource() {
        let sourceId = UUID()
        let sampleSource = PlaylistSource(
            id: sourceId,
            name: "Home Jellyfin Media Server",
            type: .jellyfin,
            urlString: "http://192.168.1.100:8096",
            username: "home_user",
            channelCount: 4
        )
        
        let sampleChannels: [Channel] = [
            Channel(
                name: "Interstellar Space (Jellyfin Movie)",
                streamURL: URL(string: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "4K"
            ),
            Channel(
                name: "Open Source Feature (Jellyfin Film)",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Sci-Fi Anthology S01E01",
                streamURL: URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!,
                groupTitle: "Series",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Extreme Adventures (Home Server)",
                streamURL: URL(string: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8")!,
                groupTitle: "Sports",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            )
        ]
        
        sources.append(sampleSource)
        channels.append(contentsOf: sampleChannels)
        saveSources()
        saveChannels()
        
        Task.detached(priority: .background) {
            await SourceHealthService.shared.probeChannels(sampleChannels)
        }
    }
    
    public func addSamplePlexSource() {
        let sourceId = UUID()
        let sampleSource = PlaylistSource(
            id: sourceId,
            name: "Plex Media Server (Cloud)",
            type: .plex,
            urlString: "https://plex.tv",
            serverToken: "sample-plex-token-xyz",
            channelCount: 3
        )
        
        let sampleChannels: [Channel] = [
            Channel(
                name: "Plex Movies: Animation Feature",
                streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "1080P"
            ),
            Channel(
                name: "Plex Movies: Cyberpunk Showcase",
                streamURL: URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!,
                groupTitle: "Movies",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "4K"
            ),
            Channel(
                name: "Plex Live TV: Global News",
                streamURL: URL(string: "https://liveproduseast.akamaized.net/us/Channel-HD-AWS-virginia-1/master.m3u8")!,
                groupTitle: "Live TV",
                logoURL: nil,
                sourceId: sourceId,
                resolutionLabel: "HD"
            )
        ]
        
        sources.append(sampleSource)
        channels.append(contentsOf: sampleChannels)
        saveSources()
        saveChannels()
        
        Task.detached(priority: .background) {
            await SourceHealthService.shared.probeChannels(sampleChannels)
        }
    }
    
    /// Adds a source and saves it, so it survives the next start.
    public func addSource(_ source: PlaylistSource) {
        sources.append(source)
        saveSources()
    }

    /// The credentials of a source: the ones in memory, or the ones in the Keychain.
    public func credentials(for sourceID: UUID) -> SourceCredentials? {
        if let source = sources.first(where: { $0.id == sourceID }) {
            let credentials = SourceCredentials(
                username: source.username,
                password: source.password,
                serverToken: source.serverToken
            )
            if !credentials.isEmpty { return credentials }
        }
        return CredentialStore.load(for: sourceID)
    }

    /// Saves the sources.
    ///
    /// The secrets go to the Keychain; the plist only gets the rest. The source
    /// list is encoded by `PlaylistSource`, which leaves the secrets out.
    func saveSources() {
        var refused = Set<UUID>()
        for source in sources {
            let credentials = SourceCredentials(
                username: source.username,
                password: source.password,
                serverToken: source.serverToken
            )
            if !CredentialStore.save(credentials, for: source.id) {
                refused.insert(source.id)
                NSLog("DRIVEPLAY could not save the credentials of source %@", source.name)
            }
        }
        if let data = sourcesData(keepingSecretsFor: refused) {
            UserDefaults.standard.set(data, forKey: Self.sourcesStorageKey)
        }
    }

    /// The sources as they are written to the plist.
    ///
    /// The secrets are left out — they live in the Keychain. A source whose
    /// secrets the Keychain refused keeps them here: an unsigned build has no
    /// keychain access at all, and losing the password would mean the user has
    /// to type it again after every restart.
    ///
    /// The **URL** of a source can carry the secrets as well — the M3U address
    /// a provider hands out is often `http://user:pass@host/get.php` — so it
    /// is redacted too, exactly like the URL of a channel.
    private func sourcesData(keepingSecretsFor keeping: Set<UUID>) -> Data? {
        let redacted = sources.map { source -> PlaylistSource in
            // A source the Keychain refused keeps everything: the plist is then
            // the only place its secrets are.
            guard !keeping.contains(source.id) else { return source }
            var copy = source
            if let url = URL(string: source.urlString) {
                copy.urlString = CredentialRedactor.redact(
                    url,
                    credentials: SourceCredentials(
                        username: source.username,
                        password: source.password,
                        serverToken: source.serverToken
                    )
                ).absoluteString
            }
            return copy
        }
        guard let data = try? JSONEncoder().encode(redacted),
              var array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for (index, source) in sources.enumerated() where keeping.contains(source.id) {
            array[index]["username"] = source.username
            array[index]["password"] = source.password
            array[index]["serverToken"] = source.serverToken
        }
        return try? JSONSerialization.data(withJSONObject: array)
    }

    /// The channel as it is written to the disk.
    ///
    /// The URLs hold the credentials, so the copy on disk gets them removed:
    /// the stream URL **and** the artwork — the image loader cannot send a
    /// header, so the token rides in the artwork's query as well.
    public static func redactedForDisk(_ channel: Channel, credentials: SourceCredentials?) -> Channel {
        var copy = channel
        copy.streamURL = CredentialRedactor.redact(channel.streamURL, credentials: credentials)
        copy.logoURL = channel.logoURL.map { CredentialRedactor.redact($0, credentials: credentials) }
        return copy
    }

    /// The channel as it is read back from the disk: the secrets are back in
    /// the URLs.
    public static func restoredForPlayback(_ channel: Channel, credentials: SourceCredentials?) -> Channel {
        var copy = channel
        copy.streamURL = CredentialRedactor.restore(channel.streamURL, credentials: credentials)
        copy.logoURL = channel.logoURL.map { CredentialRedactor.restore($0, credentials: credentials) }
        return copy
    }

    public func saveChannels() {
        rebuildIndex()
        // The URLs hold the credentials, so the copy on disk gets them removed.
        let chs = channels.map { channel -> Channel in
            Self.redactedForDisk(channel, credentials: credentials(for: channel.sourceId))
        }
        Task.detached(priority: .background) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = docs.appendingPathComponent("saved_channels.json")
            if let data = try? JSONEncoder().encode(chs) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: Self.sourcesStorageKey),
           var decoded = try? JSONDecoder().decode([PlaylistSource].self, from: data) {
            var migrated = false
            for index in decoded.indices {
                let secrets = SourceCredentials(
                    username: decoded[index].username,
                    password: decoded[index].password,
                    serverToken: decoded[index].serverToken
                )
                // An older build kept the secrets in the plist: move them to the Keychain.
                // If the Keychain refuses them, the plist keeps them (see saveSources).
                if !secrets.isEmpty, CredentialStore.save(secrets, for: decoded[index].id) {
                    migrated = true
                }
                // The Keychain is the source of truth from here on.
                if let stored = CredentialStore.load(for: decoded[index].id) {
                    decoded[index].username = stored.username
                    decoded[index].password = stored.password
                    decoded[index].serverToken = stored.serverToken
                }
            }
            self.sources = decoded
            if migrated { saveSources() }   // rewrite the plist without the secrets
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("saved_channels.json")

        let fileData = try? Data(contentsOf: fileURL)
        let legacyData = UserDefaults.standard.data(forKey: channelsStorageKey)
        let read = Self.readChannels(fileData: fileData, legacyData: legacyData)
        var loaded = read.channels
        let fromLegacyDefaults = read.fromLegacyBlob

        // The file holds the URLs without the credentials: put them back for playback.
        var needsRewrite = fromLegacyDefaults
        for index in loaded.indices {
            let credentials = credentials(for: loaded[index].sourceId)
            // Does the file still hold a secret — in the stream URL or in the
            // artwork? Then it has to be written again without it.
            if Self.redactedForDisk(loaded[index], credentials: credentials) != loaded[index] { needsRewrite = true }
            loaded[index] = Self.restoredForPlayback(loaded[index], credentials: credentials)
        }
        self.channels = loaded
        // The old plist blob held the URLs in the clear: it is not needed any
        // more — but only once the channels were really read. Removing it
        // after a failed load would throw the last copy of the library away.
        if read.removeLegacyBlob {
            UserDefaults.standard.removeObject(forKey: channelsStorageKey)
        }
        rebuildIndex()
        if needsRewrite { saveChannels() }
    }

    /// Reads a library out of the two places it can be.
    ///
    /// The file is the current home of the library, the old plist blob the
    /// fallback. The blob is only thrown away once there is a library to
    /// keep — removing it after a failed load would throw the last copy of
    /// the library away.
    public static func readChannels(fileData: Data?, legacyData: Data?) -> (channels: [Channel], fromLegacyBlob: Bool, removeLegacyBlob: Bool) {
        var loaded: [Channel] = []
        if let fileData {
            // Every channel is decoded on its own: one entry that cannot be
            // read must not empty the whole library.
            loaded = Channel.decodeList(from: fileData)
        }
        // The old plist blob is the fallback: a file that cannot be read must
        // not empty the library while the blob still holds it.
        var fromLegacyBlob = false
        if loaded.isEmpty, let legacyData {
            loaded = Channel.decodeList(from: legacyData)
            fromLegacyBlob = !loaded.isEmpty
        }
        return (loaded, fromLegacyBlob, !loaded.isEmpty)
    }
}
