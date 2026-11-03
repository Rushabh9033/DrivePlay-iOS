import XCTest
import Foundation
@testable import CarTV

/// The install helper is part of the repo, so it has to behave on any machine:
/// no phone or build path baked in, and a bounded wait when the phone is absent.
///
/// The iOS test bundle cannot spawn processes (`Foundation.Process` does not
/// exist on iOS), so the contract is checked statically here; the script's
/// runtime behaviour is exercised from the shell.
final class InstallScriptTests: XCTestCase {

    private var scriptURL: URL {
        RepositoryFixture.root.appendingPathComponent("scripts/auto_install.sh")
    }

    /// AC11: the script carries no phone identifier and no absolute path from one
    /// developer's machine — both used to be constants, so it only worked for the
    /// machine that wrote it — and it has a bounded wait instead of an endless
    /// loop, so a missing phone ends in a clear error.
    func test_AC11_install_script_has_no_hardcoded_device_and_a_bounded_wait() throws {
        try RepositoryFixture.skipUnlessPresent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        let text = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertNil(text.range(of: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}",
                                options: .regularExpression),
                     "the script must not name a specific device")
        XCTAssertFalse(text.contains("/Users/"),
                       "the script must not depend on one machine's home directory")
        XCTAssertTrue(text.contains("WAIT_SECONDS"),
                      "the wait for a device must be bounded")
        XCTAssertTrue(text.contains("no device available"),
                      "the script must say why it gave up")
    }
}
