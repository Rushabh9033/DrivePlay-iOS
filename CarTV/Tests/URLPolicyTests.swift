import XCTest
@testable import CarTV

/// App Transport Security allows plain HTTP only on the local network, so the
/// URLs the app builds have to follow the same rule.
final class URLPolicyTests: XCTestCase {

    /// AC16: local hosts may use plain HTTP; every other host has to use HTTPS.
    func test_AC16_scheme_defaults_to_https_except_for_local_hosts() {
        XCTAssertEqual(URLPolicy.scheme(forHost: "192.168.1.100"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "10.0.0.5"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "172.20.1.1"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "169.254.1.1"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "127.0.0.1"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "server.local"), "http")
        XCTAssertEqual(URLPolicy.scheme(forHost: "::1"), "http")

        XCTAssertEqual(URLPolicy.scheme(forHost: "example.com"), "https")
        XCTAssertEqual(URLPolicy.scheme(forHost: "8.8.8.8"), "https")
        XCTAssertEqual(URLPolicy.scheme(forHost: "172.32.0.1"), "https")
        XCTAssertEqual(URLPolicy.scheme(forHost: "192.169.1.1"), "https")
        XCTAssertEqual(URLPolicy.scheme(forHost: "notlocalhost.example.com"), "https")
    }

    /// AC17: an address without a scheme gets one, and the trailing slash goes.
    func test_AC17_normalized_adds_a_scheme_and_drops_the_trailing_slash() {
        XCTAssertEqual(URLPolicy.normalized("192.168.1.100:8096/"), "http://192.168.1.100:8096")
        XCTAssertEqual(URLPolicy.normalized("jellyfin.example.com"), "https://jellyfin.example.com")
        XCTAssertEqual(URLPolicy.normalized("http://1.2.3.4:8080/"), "http://1.2.3.4:8080")
        XCTAssertEqual(URLPolicy.normalized("https://x.example.com/"), "https://x.example.com")
        XCTAssertEqual(URLPolicy.normalized(""), "")
    }

    /// AC18: the host is read out of an address with a scheme, a port or a path.
    func test_AC18_host_is_read_from_scheme_port_and_path() {
        XCTAssertEqual(URLPolicy.host(of: "https://example.com/path"), "example.com")
        XCTAssertEqual(URLPolicy.host(of: "192.168.1.100:8096"), "192.168.1.100")
        XCTAssertEqual(URLPolicy.host(of: "example.com:8080/jellyfin"), "example.com")
    }

    /// AC25: a request blocked by App Transport Security says what to do.
    func test_AC25_a_blocked_plain_http_server_says_what_to_do() {
        let blocked = NSError(domain: NSURLErrorDomain,
                              code: NSURLErrorAppTransportSecurityRequiresSecureConnection)
        let message = URLPolicy.message(for: blocked)
        XCTAssertTrue(message.contains("http://"), message)
        XCTAssertTrue(message.contains("https://"), message)

        // Anything else keeps the system wording.
        let other = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(URLPolicy.message(for: other), other.localizedDescription)
    }
}
