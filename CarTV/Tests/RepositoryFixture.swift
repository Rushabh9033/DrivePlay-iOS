import Foundation
import XCTest

/// The repository's own files, read from the checkout the tests were built from.
///
/// A phone has the **app**, not the repository: the paths baked into the test
/// bundle (`#filePath`) point at the Mac it was built on, and they do not exist
/// on the device. A contract test that reads a file from the repo therefore
/// cannot run there — it skips instead of failing, because a file that is not
/// on the machine says nothing about the contract.
enum RepositoryFixture {

    /// The repository root, derived from the path of this file.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CarTV
            .deletingLastPathComponent()   // repository root
    }

    /// True when the repository is on this machine.
    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }

    /// Skips the test when the repository is not on this machine.
    static func skipUnlessPresent(file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(isPresent, "the repository is not on this machine", file: file, line: line)
    }
}
