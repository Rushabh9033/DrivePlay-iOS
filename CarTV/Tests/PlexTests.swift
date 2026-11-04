import XCTest
@testable import CarTV

/// The Plex sign-in: the account is linked in Chrome, but the phone says
/// *"No Plex media server found on this account"*.
///
/// Every one of these used to end in that one message, whichever the real
/// problem was.
final class PlexTests: XCTestCase {

    // MARK: - The answer that comes back

    /// AC127: **one odd device does not empty the whole list.**
    ///
    /// Every field of a resource was required, so a single device that left
    /// one out made the whole answer unreadable — and an unreadable answer
    /// was reported as *"this account has no media server"*.
    func test_AC127_one_odd_device_does_not_empty_the_list() throws {
        let json = """
        [
          {"name":"Living Room","clientIdentifier":"server-1","provides":"server",
           "connections":[{"uri":"http://10.0.0.5:32400","local":true,"port":32400}]},
          {"name":"Radhika's iPhone"}
        ]
        """

        let resources = try JSONDecoder().decode([PlexClient.PlexResource].self, from: Data(json.utf8))

        XCTAssertEqual(resources.count, 2)
        XCTAssertEqual(resources[0].name, "Living Room")
        XCTAssertEqual(resources[1].clientIdentifier, "", "the missing field has a default")
        XCTAssertEqual(resources[1].provides, "")
        XCTAssertNil(resources[1].connections)
    }

    /// AC128: **`provides` reads as a string and as a list.**
    ///
    /// plex.tv has answered this both as `"server"` and as `["server"]`; a
    /// decoder that only knows one of them reads **nothing**, and the server
    /// looks like it is not there.
    func test_AC128_provides_reads_as_a_string_and_as_a_list() throws {
        let asString = """
        [{"name":"Server","clientIdentifier":"a","provides":"server"}]
        """
        let asList = """
        [{"name":"Server","clientIdentifier":"a","provides":["server","player"]}]
        """

        let one = try JSONDecoder().decode([PlexClient.PlexResource].self, from: Data(asString.utf8))
        let two = try JSONDecoder().decode([PlexClient.PlexResource].self, from: Data(asList.utf8))

        XCTAssertEqual(one[0].provides, "server")
        XCTAssertTrue(two[0].provides.contains("server"))
    }

    /// AC129: **the account's own phone is not the media server.**
    ///
    /// The fallback for a resource that does not say what it is used to take
    /// *every* resource — so the account's phone could pass for the server
    /// and the source would point at the phone.
    func test_AC129_the_accounts_own_phone_is_not_the_media_server() {
        let phone = PlexClient.PlexResource(
            name: "Radhika's iPhone",
            clientIdentifier: "phone-1",
            provides: "player",
            connections: [PlexClient.PlexResource.PlexConnection(uri: "http://10.0.0.2:32500", local: true, port: 32500)]
        )

        XCTAssertNil(PlexClient.preferredServer(in: [phone]),
                     "the account's own phone was taken for the server")
    }

    /// AC130: a resource that says **nothing** about itself is only the
    /// server when it answers on a port.
    func test_AC130_a_silent_resource_is_the_server_only_when_it_answers_on_a_port() {
        let withPort = PlexClient.PlexResource(
            name: "",
            clientIdentifier: "silent-1",
            provides: "",
            connections: [PlexClient.PlexResource.PlexConnection(uri: "http://10.0.0.9:32400", local: true, port: 32400)]
        )
        let withoutPort = PlexClient.PlexResource(
            name: "",
            clientIdentifier: "silent-2",
            provides: "",
            connections: [PlexClient.PlexResource.PlexConnection(uri: "http://10.0.0.10", local: true)]
        )

        let server = PlexClient.preferredServer(in: [withPort])
        XCTAssertEqual(server?.name, "Plex Server", "a nameless server still has an address")
        XCTAssertEqual(server?.address, "http://10.0.0.9:32400")

        XCTAssertNil(PlexClient.preferredServer(in: [withoutPort]),
                     "a resource that answers on no port is not a server")
    }

    /// AC131: the relay address is asked for.
    ///
    /// `includeRelay=1` is what puts the `*.plex.direct` address of a server
    /// into the answer. Without it a phone that is not on the server's own
    /// network sees a server with **no usable address at all**.
    func test_AC131_the_relay_address_is_asked_for() {
        XCTAssertTrue(PlexClient.resourcesURL.contains("includeRelay=1"),
                      "the relay address is not asked for")
        XCTAssertTrue(PlexClient.resourcesURL.contains("includeHttps=1"))
    }

    /// AC132: **a refused account is not reported as an account without a
    /// server.**
    ///
    /// The two are different problems with different answers: one has to be
    /// signed in again, the other needs a server on the account.
    func test_AC132_a_refused_account_is_not_reported_as_an_account_without_a_server() {
        let refused = PlexClient.PlexError.refused(status: 401).errorDescription ?? ""
        let noServer = PlexClient.PlexError.noMediaServer.errorDescription ?? ""
        let unreadable = PlexClient.PlexError.unreadableAnswer.errorDescription ?? ""

        XCTAssertTrue(refused.contains("401"), "the status says what went wrong")
        XCTAssertFalse(refused.contains("no media server"))
        XCTAssertTrue(noServer.contains("no media server"))
        XCTAssertFalse(noServer.contains("401"))
        XCTAssertNotEqual(refused, noServer)
        XCTAssertNotEqual(refused, unreadable)
        XCTAssertNotEqual(noServer, unreadable)
    }
}
