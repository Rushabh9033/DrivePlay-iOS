import XCTest
@testable import CarTV

/// Covers the Xtream Codes client and the DLNA/UPnP DIDL-Lite parser.
final class SourceParserTests: XCTestCase {

    // MARK: - Xtream credential encoding

    /// A password containing `&` used to truncate the query string, so the panel
    /// received `password=p@ss` plus a junk parameter and answered 401.
    func test_Xtream_encodes_ampersand_in_password() {
        let encoded = XtreamClient.encodeCredential("p@ss&x")
        let url = URL(string: "http://host/player_api.php?username=user1&password=\(encoded)&action=get_live_categories")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertEqual(items.first { $0.name == "password" }?.value, "p@ss&x")
        XCTAssertEqual(items.first { $0.name == "username" }?.value, "user1")
        XCTAssertEqual(items.first { $0.name == "action" }?.value, "get_live_categories")
    }

    /// A password containing `#` used to truncate the URL path, so every stream
    /// endpoint pointed at a path that did not exist.
    func test_Xtream_encodes_hash_in_password_for_stream_path() {
        let encoded = XtreamClient.encodeCredential("p#ss")
        let endpoint = "http://host/live/user1/\(encoded)/123.m3u8"
        let url = URL(string: endpoint)

        XCTAssertNotNil(url)
        // `absoluteString` keeps the percent-encoding; `path` is the decoded form.
        XCTAssertEqual(url?.absoluteString, "http://host/live/user1/p%23ss/123.m3u8")
        XCTAssertEqual(url?.path, "/live/user1/p#ss/123.m3u8")
        XCTAssertNil(url?.fragment, "the stream id must stay in the path")
    }

    func test_Xtream_leaves_unreserved_characters_untouched() {
        XCTAssertEqual(XtreamClient.encodeCredential("user-1.name_x~z"), "user-1.name_x~z")
    }

    // MARK: - DLNA / UPnP DIDL-Lite

    private let twoItemDIDL = """
    <?xml version="1.0" encoding="utf-8"?>
    <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
      <item id="1">
        <dc:title>Movie One</dc:title>
        <upnp:albumArtURI>http://host/art1.jpg</upnp:albumArtURI>
        <res protocolInfo="http-get:*:video/mp4:DLNA.ORG_OP=04" duration="0:01:30">http://host/1.mp4</res>
      </item>
      <item id="2">
        <dc:title>Movie Two</dc:title>
        <upnp:albumArtURI>http://host/art2.jpg</upnp:albumArtURI>
        <res protocolInfo="http-get:*:video/mp4:DLNA.ORG_OP=04" duration="0:02:00">http://host/2.mp4</res>
      </item>
    </DIDL-Lite>
    """

    /// Two entries used to be merged into one, with the title and URL of both
    /// concatenated into a single unplayable channel.
    func test_DLNA_does_not_merge_multiple_items() {
        let item = DLNADIDLParser().parse(xmlString: twoItemDIDL)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Movie One")
        XCTAssertEqual(item?.streamURL.absoluteString, "http://host/1.mp4")
        XCTAssertEqual(item?.artworkURL?.absoluteString, "http://host/art1.jpg")
    }

    func test_DLNA_reads_mime_type_out_of_protocol_info() {
        let item = DLNADIDLParser().parse(xmlString: twoItemDIDL)
        XCTAssertEqual(item?.mimeType, "video/mp4")
    }

    func test_DLNA_reads_duration() {
        let item = DLNADIDLParser().parse(xmlString: twoItemDIDL)
        XCTAssertEqual(item?.duration, "0:01:30")
    }

    func test_DLNA_returns_nil_when_there_is_no_resolvable_url() {
        let didl = """
        <DIDL-Lite>
          <item id="1"><dc:title>No Media</dc:title></item>
        </DIDL-Lite>
        """
        XCTAssertNil(DLNADIDLParser().parse(xmlString: didl))
    }

    func test_DLNA_parsing_twice_does_not_accumulate_state() {
        let parser = DLNADIDLParser()
        let first = parser.parse(xmlString: twoItemDIDL)
        let second = parser.parse(xmlString: twoItemDIDL)

        XCTAssertEqual(first?.title, second?.title)
        XCTAssertEqual(first?.streamURL, second?.streamURL)
    }

    // MARK: - Plex pin

    /// Plex's pin response carries `expiresIn` and `createdAt` — never `expiresAt`.
    /// Requiring an `expiresAt` key made every response fail to decode, so Plex
    /// sign-in could not complete at all.
    func test_AC7_PlexPin_decodes_the_response_Plex_actually_returns() throws {
        let json = """
        {"id":123456,"code":"RN9H","product":"","trusted":false,
         "clientIdentifier":"CarTV-iOS-Player","expiresIn":1800,
         "createdAt":"2026-10-31T12:00:00Z"}
        """
        let pin = try JSONDecoder().decode(PlexClient.PlexPin.self, from: Data(json.utf8))

        XCTAssertEqual(pin.id, 123456)
        XCTAssertEqual(pin.code, "RN9H")
        XCTAssertEqual(pin.expiresIn, 1800)
        XCTAssertNil(pin.authToken)
    }

    /// Once the user links the code, Plex adds the token.
    func test_AC8_PlexPin_decodes_an_authenticated_pin() throws {
        let json = """
        {"id":123456,"code":"RN9H","authToken":"tok-123","expiresIn":1800,
         "createdAt":"2026-10-31T12:00:00Z"}
        """
        let pin = try JSONDecoder().decode(PlexClient.PlexPin.self, from: Data(json.utf8))

        XCTAssertEqual(pin.authToken, "tok-123")
    }
}
