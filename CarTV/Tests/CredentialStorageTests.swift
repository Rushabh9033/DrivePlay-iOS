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

    /// AC90: the artwork loses its token on disk and gets it back.
    ///
    /// The image loader cannot send a header, so the token rides in the
    /// artwork's query — and the artwork was written to the library file and
    /// to the watch history in the clear.
    func test_AC90_the_artwork_loses_its_token_on_disk() throws {
        let credentials = SourceCredentials(serverToken: "tok-123")
        let channel = Channel(
            name: "Movie",
            streamURL: URL(string: "http://example.com/Videos/1/stream.mp4?static=true&api_key=tok-123")!,
            logoURL: URL(string: "http://example.com/Items/1/Images/Primary?fillWidth=400&api_key=tok-123")!
        )

        let onDisk = PlaylistStore.redactedForDisk(channel, credentials: credentials)
        XCTAssertFalse(onDisk.streamURL.absoluteString.contains("tok-123"))
        let artwork = try XCTUnwrap(onDisk.logoURL)
        XCTAssertFalse(artwork.absoluteString.contains("tok-123"))

        let readBack = PlaylistStore.restoredForPlayback(onDisk, credentials: credentials)
        XCTAssertEqual(readBack.streamURL, channel.streamURL)
        XCTAssertEqual(readBack.logoURL, channel.logoURL)
    }

    /// AC91: the watch history plays the real URL, not the placeholder.
    ///
    /// The history kept the *redacted* URL in memory, so the "watch again"
    /// row played a URL with `__dp_token__` in it until the app was
    /// restarted.
    func test_AC91_the_watch_history_plays_the_real_url() throws {
        let previousHistory = UserDefaults.standard.data(forKey: "cartv_playlist_watch_history")
        let previousSources = PlaylistStore.shared.sources
        defer {
            PlaylistStore.shared.sources = previousSources
            if let previousHistory {
                UserDefaults.standard.set(previousHistory, forKey: "cartv_playlist_watch_history")
            } else {
                UserDefaults.standard.removeObject(forKey: "cartv_playlist_watch_history")
            }
        }
        UserDefaults.standard.removeObject(forKey: "cartv_playlist_watch_history")

        let source = PlaylistSource(
            name: "Jellyfin",
            type: .jellyfin,
            urlString: "http://example.com",
            serverToken: "tok-123"
        )
        PlaylistStore.shared.sources = [source]

        let channel = Channel(
            name: "Movie",
            streamURL: URL(string: "http://example.com/Videos/1/stream.mp4?api_key=tok-123")!,
            logoURL: URL(string: "http://example.com/Items/1/Images/Primary?api_key=tok-123")!,
            sourceId: source.id
        )
        let store = WatchHistoryStore()
        store.recordWatch(channel)

        let item = try XCTUnwrap(store.history.first)
        // The item in memory plays the real URL…
        XCTAssertTrue(item.streamURL.absoluteString.contains("tok-123"))
        XCTAssertTrue(try XCTUnwrap(item.logoURL).absoluteString.contains("tok-123"))
        // …and the copy on disk holds none of it.
        let onDisk = WatchHistoryStore.redactedForDisk(
            item,
            credentials: SourceCredentials(serverToken: "tok-123")
        )
        XCTAssertFalse(onDisk.streamURL.absoluteString.contains("tok-123"))
        XCTAssertFalse(try XCTUnwrap(onDisk.logoURL).absoluteString.contains("tok-123"))
    }

    /// AC150: the screen stream's token is wide enough to be a lock.
    ///
    /// The stream is the phone's screen, and it is served over the local
    /// network — so the token in its path is the only thing that keeps it
    /// private. Eight hex characters are 32 bits, and 2³² guesses is a
    /// weekend's work for anyone on the same Wi-Fi.
    func test_AC150_the_screen_streams_token_is_wide_enough_to_be_a_lock() throws {
        let writer = try XCTUnwrap(LiveScreenWriter.make(), "the encoder could not start")
        let server = ScreenStreamServer(writer: writer)

        XCTAssertGreaterThanOrEqual(server.token.count, 32,
                                    "the token is too narrow to be a lock")
        XCTAssertFalse(server.token.contains("-"), "the token must be one unbroken string")

        let other = ScreenStreamServer(writer: writer)
        XCTAssertNotEqual(server.token, other.token, "two servers share a token")
    }

    /// AC151: a URL that carries a password is not written to the log as it is.
    ///
    /// The device's log is readable by anything attached to the phone — an
    /// Xcode console, `idevicesyslog`, a sysdiagnose — and a stream URL
    /// carries the account's token. The log keeps the host and the name of
    /// the file, which is what says *which* stream failed, and nothing else.
    func test_AC151_a_url_that_carries_a_password_is_not_logged_as_it_is() throws {
        let url = try XCTUnwrap(URL(string:
            "http://user:pass-secret@example.com:8080/live/user/pass-secret/12345.ts?api_key=token-secret"))

        let safe = CredentialRedactor.safeForLog(url)
        XCTAssertFalse(safe.contains("pass-secret"), "the password reached the log: \(safe)")
        XCTAssertFalse(safe.contains("token-secret"), "the token reached the log: \(safe)")
        XCTAssertFalse(safe.contains("user"), "the user name reached the log: \(safe)")
        XCTAssertTrue(safe.contains("example.com"), "the log lost the host: \(safe)")
        XCTAssertTrue(safe.contains("12345.ts"), "the log lost the file name: \(safe)")

        // A string that is not a URL at all is not written out either — it
        // may still be a password the user pasted.
        XCTAssertEqual(CredentialRedactor.safeForLog("pass-secret"), "<not a URL>")
    }
}
