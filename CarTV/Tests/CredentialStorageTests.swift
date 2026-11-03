import XCTest
@testable import CarTV

/// The secrets of a source must not be readable from the app's own files: they
/// live in the Keychain, and the copies on disk hold placeholders.
@MainActor
final class CredentialStorageTests: XCTestCase {

    /// AC19: encoding a source leaves the secrets out.
    func test_AC19_encoding_a_source_leaves_the_secrets_out() throws {
        let source = PlaylistSource(
            name: "Provider",
            type: .xtream,
            urlString: "http://example.com:8080",
            username: "user-secret",
            password: "pass-secret",
            serverToken: "token-secret"
        )
        let data = try JSONEncoder().encode(source)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("user-secret"))
        XCTAssertFalse(json.contains("pass-secret"))
        XCTAssertFalse(json.contains("token-secret"))

        let decoded = try JSONDecoder().decode(PlaylistSource.self, from: data)
        XCTAssertNil(decoded.username)
        XCTAssertNil(decoded.password)
        XCTAssertNil(decoded.serverToken)
        XCTAssertEqual(decoded.id, source.id)
        XCTAssertEqual(decoded.urlString, source.urlString)
    }

    /// AC20: a source saved by an older build still decodes its secrets, so they
    /// can be moved into the Keychain.
    func test_AC20_a_legacy_source_still_decodes_its_secrets() throws {
        let id = UUID()
        let legacy = """
        {"id":"\(id.uuidString)","name":"Old","type":"Xtream Codes","urlString":"http://example.com:8080",\
        "username":"old-user","password":"old-pass","lastUpdated":0,"channelCount":3,"isEnabled":true}
        """
        let decoded = try JSONDecoder().decode(PlaylistSource.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.username, "old-user")
        XCTAssertEqual(decoded.password, "old-pass")
        XCTAssertEqual(decoded.channelCount, 3)
    }

    /// AC21: the Keychain keeps the secrets and hands them back.
    func test_AC21_the_keychain_keeps_the_secrets() {
        let id = UUID()
        defer { CredentialStore.delete(for: id) }
        let credentials = SourceCredentials(username: "u", password: "p", serverToken: "t")
        XCTAssertTrue(CredentialStore.save(credentials, for: id))
        XCTAssertEqual(CredentialStore.load(for: id), credentials)
        CredentialStore.delete(for: id)
        XCTAssertNil(CredentialStore.load(for: id))
    }

    /// AC22: a stream URL loses its secrets on disk and gets them back.
    func test_AC22_stream_urls_are_redacted_and_restored() {
        // The path form the Xtream parser builds: /live/<user>/<pass>/<id>.m3u8
        let pathCredentials = SourceCredentials(username: "user", password: "p@ss&x")
        let xtream = URL(string: "http://example.com:8080/live/user/p%40ss%26x/123.m3u8")!
        let redacted = CredentialRedactor.redact(xtream, credentials: pathCredentials)
        XCTAssertFalse(redacted.absoluteString.contains("/user/"))
        XCTAssertFalse(redacted.absoluteString.contains("p%40ss%26x"))
        XCTAssertTrue(redacted.absoluteString.contains(CredentialRedactor.userPlaceholder))
        XCTAssertEqual(CredentialRedactor.restore(redacted, credentials: pathCredentials), xtream)

        // The user info form: http://user:password@host/...
        let userInfoCredentials = SourceCredentials(username: "user", password: "s3cret")
        let userInfo = URL(string: "http://user:s3cret@example.com/live/1.m3u8")!
        let redactedUserInfo = CredentialRedactor.redact(userInfo, credentials: userInfoCredentials)
        XCTAssertFalse(redactedUserInfo.absoluteString.contains("s3cret"))
        XCTAssertEqual(CredentialRedactor.restore(redactedUserInfo, credentials: userInfoCredentials), userInfo)

        // The query form the Jellyfin client builds: ?api_key=<token>
        let queryCredentials = SourceCredentials(serverToken: "tok-123")
        let jellyfin = URL(string: "http://example.com/Videos/1/stream.mp4?static=true&api_key=tok-123")!
        let redactedJellyfin = CredentialRedactor.redact(jellyfin, credentials: queryCredentials)
        XCTAssertFalse(redactedJellyfin.absoluteString.contains("tok-123"))
        XCTAssertEqual(CredentialRedactor.restore(redactedJellyfin, credentials: queryCredentials), jellyfin)
    }

    /// AC23: saving the sources puts the secrets in the Keychain, not in the plist.
    func test_AC23_saved_sources_keep_the_secrets_out_of_user_defaults() throws {
        let previous = UserDefaults.standard.data(forKey: PlaylistStore.sourcesStorageKey)
        defer {
            if let previous = previous {
                UserDefaults.standard.set(previous, forKey: PlaylistStore.sourcesStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: PlaylistStore.sourcesStorageKey)
            }
        }

        let source = PlaylistSource(
            name: "Provider",
            type: .xtream,
            urlString: "http://example.com:8080",
            username: "user-secret",
            password: "pass-secret"
        )
        defer { CredentialStore.delete(for: source.id) }

        let store = PlaylistStore()
        store.sources = [source]
        store.saveSources()

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: PlaylistStore.sourcesStorageKey))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("user-secret"))
        XCTAssertFalse(json.contains("pass-secret"))
        XCTAssertEqual(CredentialStore.load(for: source.id)?.password, "pass-secret")
    }
}
