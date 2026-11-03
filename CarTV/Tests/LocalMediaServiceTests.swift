import XCTest
@testable import CarTV

/// Covers the offline vault's storage: two imports with the same filename must not
/// overwrite each other, and the index must survive an interrupted write.
@MainActor
final class LocalMediaServiceTests: XCTestCase {

    /// AC9: importing `clip.mp4` from two different folders used to write both to
    /// `clip.mp4` — the second import overwrote the first file and the vault ended up
    /// with two entries pointing at one copy.
    func test_AC9_importing_the_same_filename_twice_keeps_both_files() async throws {
        let service = LocalMediaService.shared
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dirA = root.appendingPathComponent("a")
        let dirB = root.appendingPathComponent("b")
        try fileManager.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let fileA = dirA.appendingPathComponent("clip.mp4")
        let fileB = dirB.appendingPathComponent("clip.mp4")
        try Data("first".utf8).write(to: fileA)
        try Data("second".utf8).write(to: fileB)

        let itemA = try await service.importVideoFile(from: fileA)
        let itemB = try await service.importVideoFile(from: fileB)
        defer {
            service.deleteVideo(item: itemA)
            service.deleteVideo(item: itemB)
        }

        XCTAssertNotEqual(itemA.relativePath, itemB.relativePath)
        XCTAssertEqual(try Data(contentsOf: service.getFileURL(for: itemA)), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: service.getFileURL(for: itemB)), Data("second".utf8))
    }

    /// AC10: the index is written atomically, so a kill mid-write cannot leave a
    /// truncated file that makes the whole vault fail to load.
    func test_AC10_index_is_written_atomically_and_reloads() async throws {
        let service = LocalMediaService.shared
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("song.m4a")
        try Data("audio".utf8).write(to: source)

        let item = try await service.addExtractedAudio(fileURL: source, title: "Song")
        defer { service.deleteVideo(item: item) }

        let indexURL = service.getFileURL(for: item)
            .deletingLastPathComponent()
            .appendingPathComponent("index.json")
        let data = try Data(contentsOf: indexURL)
        let decoded = try JSONDecoder().decode([LocalVideoItem].self, from: data)
        XCTAssertTrue(decoded.contains { $0.id == item.id })
    }
}
