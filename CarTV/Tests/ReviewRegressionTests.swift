import XCTest
import CarPlay
import Network
import UIKit
@testable import CarTV

/// The regressions the review of 2026-11-03 found.
///
/// Every test here names the acceptance criterion it covers.
final class ReviewRegressionTests: XCTestCase {

    // MARK: - The parsers

    /// AC70: the title of the **container** is not the title of the first item.
    ///
    /// A DIDL-Lite document carries a `<dc:title>` for the folder the items
    /// live in. That name used to be glued onto the first item.
    func test_AC70_the_dlna_container_title_is_not_the_title_of_the_first_item() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <container id="c1" parentID="0"><dc:title>My Movies</dc:title></container>
          <item id="i1" parentID="c1">
            <dc:title>Actual Movie</dc:title>
            <res protocolInfo="http-get:*:video/mp4:DLNA.ORG_OP=04">http://example.com/movie.mp4</res>
          </item>
        </DIDL-Lite>
        """

        let item = DLNADIDLParser().parse(xmlString: xml)

        XCTAssertEqual(item?.title, "Actual Movie")
    }

    /// AC71: an item carries several `<res>` elements — one per protocol and
    /// bitrate. Only the first one is the stream; the others used to be
    /// concatenated into an address that does not exist.
    func test_AC71_the_dlna_parser_takes_the_first_res_of_an_item() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <item id="i1" parentID="c1">
            <dc:title>Movie</dc:title>
            <res protocolInfo="http-get:*:video/mp4:DLNA.ORG_OP=04">http://example.com/movie.mp4</res>
            <res protocolInfo="http-get:*:video/mp4:DLNA.ORG_OP=04">http://example.com/movie-hd.mp4</res>
          </item>
        </DIDL-Lite>
        """

        let item = DLNADIDLParser().parse(xmlString: xml)

        XCTAssertEqual(item?.streamURL.absoluteString, "http://example.com/movie.mp4")
    }

    /// AC72: an attribute whose value is not quoted is still read.
    ///
    /// A provider that writes `tvg-id=abc123` instead of `tvg-id="abc123"`
    /// used to lose its id — and with it the channel's identity.
    func test_AC72_the_m3u_parser_keeps_an_unquoted_attribute_value() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1 tvg-id=abc123 group-title=News,News One
        https://example.com/news.m3u8
        """

        let channels = try M3UParser().parse(content: fixture)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].tvgId, "abc123")
        XCTAssertEqual(channels[0].groupTitle, "News")
    }

    /// AC73: a channel that says "HD" is not relabelled "720P".
    ///
    /// The app must not claim a resolution the provider never gave.
    func test_AC73_the_m3u_parser_does_not_relabel_hd() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1,Some Channel HD
        https://example.com/hd.m3u8
        """

        let channels = try M3UParser().parse(content: fixture)

        XCTAssertEqual(channels[0].resolutionLabel, "HD")
    }

    // MARK: - The library

    /// AC74: one entry that cannot be read does not empty the library.
    ///
    /// The library is the one thing the user cannot get back — and the next
    /// save would overwrite the file with nothing.
    func test_AC74_the_library_survives_one_entry_that_cannot_be_read() throws {
        let json = """
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Good One","streamURL":"https://example.com/a.m3u8","groupTitle":"Sports"},
          {"name":"Broken","streamURL":42},
          {"id":"33333333-3333-3333-3333-333333333333","name":"Good Two","streamURL":"https://example.com/b.m3u8","groupTitle":"News"}
        ]
        """

        let channels = Channel.decodeList(from: Data(json.utf8))

        XCTAssertEqual(channels.count, 2, "the entry that cannot be read must not take the others with it")
        XCTAssertEqual(channels.map(\.name), ["Good One", "Good Two"])
    }

    /// AC75: the old library is not thrown away while it cannot be read.
    ///
    /// The file is the current home of the library and the old plist blob the
    /// fallback. The blob may only go once there is a library to keep.
    @MainActor
    func test_AC75_the_old_library_is_not_thrown_away_while_it_cannot_be_read() {
        let legacy = Data("""
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Kept","streamURL":"https://example.com/a.m3u8","groupTitle":"Sports"}]
        """.utf8)

        // The file cannot be read: the blob is the fallback and holds the
        // library.
        let fallback = PlaylistStore.readChannels(fileData: nil, legacyData: legacy)
        XCTAssertEqual(fallback.channels.count, 1, "the blob holds the library when the file cannot be read")
        XCTAssertTrue(fallback.fromLegacyBlob)
        XCTAssertTrue(fallback.removeLegacyBlob, "the blob may go once the library was really read")

        // Nothing can be read at all: the blob is kept — it is the last copy.
        let nothing = PlaylistStore.readChannels(fileData: nil, legacyData: Data("not json".utf8))
        XCTAssertTrue(nothing.channels.isEmpty)
        XCTAssertFalse(nothing.removeLegacyBlob, "the last copy of the library must not be thrown away")
    }

    // MARK: - The servers

    /// AC76: the whole library is read, page by page.
    ///
    /// A single request with `Limit=100` silently truncated the library: the
    /// user saw the first hundred items and nothing else.
    func test_AC76_the_jellyfin_library_is_read_page_by_page() async throws {
        StubJellyfinServer.items = (1...250).map { ["Id": "id\($0)", "Name": "Item \($0)", "Type": "Movie"] }
        StubJellyfinServer.requested = []
        defer { StubJellyfinServer.reset() }

        let client = JellyfinClient(session: StubJellyfinServer.session())
        let channels = try await client.fetchLibraryChannels(serverUrl: "http://server.local",
                                                             token: "tok",
                                                             userId: "u1",
                                                             sourceId: UUID())

        XCTAssertEqual(channels.count, 250, "the library was cut short")
        XCTAssertEqual(StubJellyfinServer.requested.count, 2, "the library must be read page by page")
    }

    /// AC77: the artwork carries the token.
    ///
    /// The artwork is loaded by the image loader, which cannot send the token
    /// header — so the token has to be in the query.
    func test_AC77_the_jellyfin_artwork_carries_the_token() async throws {
        StubJellyfinServer.items = [["Id": "id1", "Name": "Item 1", "Type": "Movie"]]
        StubJellyfinServer.requested = []
        defer { StubJellyfinServer.reset() }

        let client = JellyfinClient(session: StubJellyfinServer.session())
        let channels = try await client.fetchLibraryChannels(serverUrl: "http://server.local",
                                                             token: "the-token",
                                                             userId: "u1",
                                                             sourceId: UUID())

        let artwork = try XCTUnwrap(channels.first?.logoURL)
        XCTAssertTrue(artwork.absoluteString.contains("api_key=the-token"),
                      "the artwork URL has no token: \(artwork.absoluteString)")
    }

    /// AC78: a Plex source points at the account's **own** media server.
    ///
    /// plex.tv is the cloud API, not the server — a source that points at it
    /// can never list a file.
    func test_AC78_a_plex_source_points_at_the_accounts_own_server() throws {
        let local = PlexClient.PlexResource(
            name: "Living Room",
            clientIdentifier: "abc",
            provides: "server",
            connections: [PlexClient.PlexResource.PlexConnection(uri: "http://10.0.0.5:32400", local: true)]
        )
        let remote = PlexClient.PlexResource(
            name: "Away",
            clientIdentifier: "def",
            provides: "server",
            connections: [PlexClient.PlexResource.PlexConnection(uri: "https://1-2-3-4.plex.direct:32400", local: false)]
        )

        let localServer = try XCTUnwrap(PlexClient.preferredServer(in: [local]))
        XCTAssertEqual(localServer.name, "Living Room")
        XCTAssertEqual(localServer.address, "http://10.0.0.5:32400")

        // The local address wins over the remote one.
        let both = try XCTUnwrap(PlexClient.preferredServer(in: [remote, local]))
        XCTAssertEqual(both.address, "http://10.0.0.5:32400")

        // A server without a connection cannot be used at all.
        let blind = PlexClient.PlexResource(name: "Blind", clientIdentifier: "ghi", provides: "server", connections: [])
        XCTAssertNil(PlexClient.preferredServer(in: [blind]))
    }

    // MARK: - The player

    /// AC79: only the player changes the track.
    ///
    /// The picker used to write the name of the track itself, which moved a
    /// checkmark and changed nothing. The selection is now read-only from the
    /// outside, and a track that is not there is not selected.
    @MainActor
    func test_AC79_only_the_player_changes_the_track() {
        let manager = PlaybackManager()

        XCTAssertEqual(manager.selectedAudioTrack, "Default")
        XCTAssertEqual(manager.selectedSubtitleTrack, "Off")

        // A track that is not there must not be selected.
        manager.selectAudioTrack(named: "English")
        XCTAssertEqual(manager.selectedAudioTrack, "Default", "a track that is not there must not be selected")
        manager.selectSubtitleTrack(named: "English")
        XCTAssertEqual(manager.selectedSubtitleTrack, "Off", "a track that is not there must not be selected")
    }



    // MARK: - The relay

    /// AC84: an announcement that never ends is dropped.
    ///
    /// The extension sends the address in one line. A peer that keeps sending
    /// without ever sending a newline must not be able to grow the buffer
    /// without end.
    func test_AC84_an_announcement_that_never_ends_is_dropped() async throws {
        let port: UInt16 = 47411
        let listener = ScreenRelayListener(port: port)
        var announced = false
        listener.onStream = { _, _ in announced = true }
        try listener.start()
        defer { listener.stop() }

        let controlPort = try XCTUnwrap(NWEndpoint.Port(rawValue: port))
        let connection = NWConnection(host: .ipv4(.loopback), port: controlPort, using: .tcp)
        let ready = expectation(description: "the connection is up")
        let dropped = expectation(description: "the connection was dropped")
        // The connection can report the drop twice — once as `.failed`, once
        // as `.cancelled` — and an expectation that is fulfilled twice throws
        // inside the handler, which kills the whole test run.
        let lock = NSLock()
        var hasDropped = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.fulfill()
            case .failed, .cancelled:
                lock.lock()
                let first = !hasDropped
                hasDropped = true
                lock.unlock()
                if first { dropped.fulfill() }
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "com.rushabh.cartvv.tests.relay.limit"))

        // Wait for the connection, then send far more than one line without
        // ever sending the newline that ends it.
        await fulfillment(of: [ready], timeout: 10)

        connection.send(content: Data(repeating: 0x41, count: 8000), completion: .contentProcessed { _ in })

        await fulfillment(of: [dropped], timeout: 20)
        XCTAssertFalse(announced, "no address was announced")
        connection.cancel()
    }

    // MARK: - The phone

    /// AC85: the device generates its orientation notifications.
    ///
    /// The notification is only posted while the device is generating them —
    /// without that the docked player never rotates into full screen.
    func test_AC85_the_device_generates_its_orientation_notifications() {
        let monitor = DeviceOrientationMonitor()
        // The app itself may be generating them already — leave it as it was.
        let wasGenerating = UIDevice.current.isGeneratingDeviceOrientationNotifications
        defer {
            if wasGenerating { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        }

        monitor.start()
        XCTAssertTrue(UIDevice.current.isGeneratingDeviceOrientationNotifications,
                      "the rotate handler would never run")

        monitor.stop()
        // The monitor must not switch off generation it did not start.
        XCTAssertEqual(UIDevice.current.isGeneratingDeviceOrientationNotifications, wasGenerating)
    }

    // MARK: - The vault

    /// AC86: a copy that cannot happen creates no vault entry.
    ///
    /// An entry that points at a file which was never written is a broken
    /// entry the user cannot play and cannot remove.
    @MainActor
    func test_AC86_a_failed_copy_creates_no_vault_entry() async throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cartv-ac86-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = LocalMediaService(storageDirectory: vault)
        let before = service.localVideos.count

        let missing = vault.appendingPathComponent("does-not-exist-\(UUID().uuidString).m4a")
        do {
            _ = try await service.addExtractedAudio(fileURL: missing, title: "Nothing")
            XCTFail("a copy that cannot happen must throw")
        } catch {
            // The copy failed — and nothing was added to the vault.
        }

        XCTAssertEqual(service.localVideos.count, before, "a broken entry was added to the vault")
    }

    /// AC87: the temporary copy of an import is removed.
    ///
    /// The transferable's file is a copy in the temporary directory — every
    /// photo imported used to leave a full-size copy behind.
    @MainActor
    func test_AC87_the_temporary_copy_of_an_import_is_removed() async throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cartv-ac87-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let service = LocalMediaService(storageDirectory: vault)

        let temporary = vault.appendingPathComponent("photo-\(UUID().uuidString).mp4")
        try Data("not really a movie".utf8).write(to: temporary)

        let item = try await service.importTemporaryVideo(from: temporary)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path),
                       "the temporary copy was left behind")
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.getFileURL(for: item).path),
                      "the vault has no copy of its own")
    }

    /// AC88: the extractor can be used again after a result.
    ///
    /// The sheet hid its button as soon as an extraction had finished, so the
    /// extractor could be used exactly once.
    @MainActor
    func test_AC88_the_extractor_can_be_used_again_after_a_result() {
        let extractor = AudioExtractorService()
        extractor.lastExtractedItem = LocalVideoItem(title: "Track",
                                                     relativePath: "track.m4a",
                                                     fileSize: 1024,
                                                     duration: 12,
                                                     resolution: "AUDIO",
                                                     isAudioOnly: true)

        XCTAssertTrue(extractor.canStartExtraction,
                      "a result on the screen must not disable the button")
    }

    /// AC89: a search query with spaces around it still matches.
    ///
    /// The query is trimmed once, and the trimmed value is what every match
    /// is made against — a trailing space used to hide every result.
    @MainActor
    func test_AC89_a_search_query_with_spaces_around_it_still_matches() {
        let store = PlaylistStore()
        store.channels = [
            Channel(name: "Sky Sports", streamURL: URL(string: "https://example.com/a.m3u8")!, groupTitle: "Sports"),
            Channel(name: "CNN", streamURL: URL(string: "https://example.com/b.m3u8")!, groupTitle: "News")
        ]
        store.rebuildIndex()

        store.searchQuery = "  sports  "

        XCTAssertEqual(store.trimmedSearchQuery, "sports")
        XCTAssertEqual(store.groups.flatMap(\.channels).map(\.name), ["Sky Sports"])
    }

    // MARK: - The browser mechanism

    /// AC155: a dead web process keeps the address the tab was on.
    ///
    /// The crash handler used to empty the tab's address, and an empty
    /// address **is** the start page — so a page whose web process died was
    /// thrown away and the user was back at the home screen. That is the
    /// user's *"it crash the browser tab and redirect tom home screen"*.
    ///
    /// The address is kept now, and the page is reloaded **once**: a reload in
    /// a loop loads the page that killed the process again, kills it again,
    /// and takes the app down with it.
    @MainActor
    func test_AC155_a_dead_web_process_keeps_the_address_the_tab_was_on() {
        // A port nothing listens on: the load fails at once, and no traffic
        // leaves the phone.
        let tab = BrowserTabItem(title: "Page", urlString: "https://127.0.0.1/")

        XCTAssertTrue(tab.handleWebProcessDeath(),
                      "the first death must load the page again")
        XCTAssertFalse(tab.handleWebProcessDeath(),
                       "a dead page must not be reloaded in a loop")

        XCTAssertEqual(tab.urlString, "https://127.0.0.1/",
                       "the tab was sent back to the start page")
        XCTAssertEqual(tab.title, "The page crashed",
                       "the tab does not say what happened")
    }

    /// AC156: the address bar is not filled over what the user typed.
    ///
    /// The bar showed the page's address when it gained the focus — over the
    /// text the user had already typed. The typing then looked like it did
    /// nothing at all.
    func test_AC156_the_address_bar_is_not_filled_over_what_the_user_typed() {
        var boxes = BrowserAddressBoxes()
        boxes.address = "sky sports"

        boxes.beginEditingAddress(currentURL: "https://example.com/")

        XCTAssertEqual(boxes.address, "sky sports",
                       "the address bar was filled over the text the user typed")
    }

    /// AC157: the browser's two search boxes keep their own text.
    ///
    /// The address bar at the bottom and the start page's own search box used
    /// to share **one** piece of state — so what was typed in one of them
    /// appeared in the other, and the change handlers wiped it.
    func test_AC157_the_browsers_two_search_boxes_keep_their_own_text() {
        var boxes = BrowserAddressBoxes()
        boxes.address = "sky sports"
        boxes.startPageQuery = "poki"

        XCTAssertEqual(boxes.address, "sky sports",
                       "the start page's text went into the address bar")
        XCTAssertEqual(boxes.startPageQuery, "poki",
                       "the address bar's text went into the start page")
    }

    // MARK: - Helpers

    private func channel(_ name: String, group: String = "Sports") -> Channel {
        Channel(name: name,
                streamURL: URL(string: "https://example.com/\(name).m3u8")!,
                groupTitle: group)
    }


}

/// A Jellyfin server that answers out of the test itself.
private final class StubJellyfinServer: URLProtocol {
    /// The items the server holds.
    static var items: [[String: Any]] = []
    /// The requests the client made.
    static var requested: [URL] = []

    static func reset() {
        items = []
        requested = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubJellyfinServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requested.append(url)

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let start = Int(query.first(where: { $0.name == "StartIndex" })?.value ?? "0") ?? 0
        let limit = Int(query.first(where: { $0.name == "Limit" })?.value ?? "100") ?? 100
        let slice = Array(Self.items[min(max(start, 0), Self.items.count)...].prefix(limit))

        let body: [String: Any] = ["Items": slice, "TotalRecordCount": Self.items.count]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let response = HTTPURLResponse(url: url,
                                             statusCode: 200,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
