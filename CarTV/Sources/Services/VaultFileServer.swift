import Foundation
import Network
import Security

/// Serves **one** file of the vault over HTTP.
///
/// The car's display is fed by the system's own video target — a process that
/// runs **outside** the app's sandbox. A `file://` URL inside the container is
/// invisible to it: the item fails with -11870
/// (`AVErrorExternalPlaybackNotSupportedForAsset`) the moment the car's route
/// takes the picture, and the video dies on the phone **and** on the car. An
/// HTTP URL on the loopback can be fetched by every process on the phone, so
/// the same file plays on the car.
///
/// The file is the user's own media, so every path carries a token — the same
/// 128 bits the live screen stream uses.
final class VaultFileServer {

    /// The token every path carries.
    ///
    /// 32 bytes from the system's random source — 256 bits, so guessing one is
    /// hopeless. The hex needs no escaping in a URL path.
    let token: String

    /// Where the file is served, once the server is up.
    private(set) var servedURL: URL?

    private let fileURL: URL
    private let fileSize: Int64
    private let contentType: String
    private let fileName: String
    private let queue = DispatchQueue(label: "com.rushabh.cartvv.vault.server")
    private var listener: NWListener?

    /// `nil` when the file is not there — the caller plays the file itself.
    init?(fileURL: URL) {
        guard let token = Self.makeToken(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, size.int64Value > 0 else { return nil }
        self.token = token
        self.fileURL = fileURL
        self.fileSize = size.int64Value
        self.contentType = Self.contentType(for: fileURL)
        // The name only carries the kind of file: the vault's own names are the
        // user's, and they need no escaping in a URL.
        let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        self.fileName = "vault.\(ext)"
    }

    /// Starts the server and returns the URL the file is served at.
    ///
    /// The port is only known once the listener is bound, so the call waits for
    /// it — a few milliseconds.
    func start() -> URL? {
        let bound = BoundPort()
        let semaphore = DispatchSemaphore(value: 0)
        do {
            // The **loopback** interface only, like the app's own relay: a
            // listener on every interface asks a phone for the local-network
            // permission first, and the user's own media has no business on
            // the network.
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    bound.set(self?.listener?.port?.rawValue)
                    semaphore.signal()
                case .failed:
                    semaphore.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        } catch {
            return nil
        }
        _ = semaphore.wait(timeout: .now() + 3)
        guard let port = bound.get(),
              let url = URL(string: "http://127.0.0.1:\(port)/\(token)/\(fileName)") else { return nil }
        servedURL = url
        return url
    }

    func stop() {
        listener?.cancel()
        listener = nil
        servedURL = nil
    }

    // MARK: - Requests

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()

        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
                guard let self, let data, error == nil else {
                    connection.cancel()
                    return
                }
                buffer.append(data)
                // A request that never ends must not eat the memory: the server
                // is reachable from the whole local network.
                guard buffer.count <= 16 * 1024 else {
                    connection.cancel()
                    return
                }
                guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    pump()
                    return
                }
                let head = String(decoding: buffer[buffer.startIndex..<end.upperBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                let lines = head.components(separatedBy: "\r\n")
                let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let range = lines.first(where: { $0.lowercased().hasPrefix("range:") })
                    .flatMap(Self.parseRange)
                // The connection stays open: the player asks for the next
                // piece of the file on the very same connection.
                self.respond(path: path, range: range, on: connection) { pump() }
            }
        }
        pump()
    }

    private func respond(path: String, range: ClosedRange<Int>?, on connection: NWConnection, then: @escaping () -> Void) {
        // The path carries the token, and the token is compared in **constant
        // time**: a timing difference would say how much of it was guessed
        // right.
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 3,
              Self.constantTimeEquals(String(segments[1]), token),
              segments[2] == fileName else {
            send(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8), on: connection, then: then)
            return
        }
        let size = Int(fileSize)
        let start = max(0, range?.lowerBound ?? 0)
        let end = min(size - 1, range?.upperBound ?? size - 1)
        guard start <= end else {
            send(status: "416 Range Not Satisfiable", type: "text/plain", body: Data("Not found".utf8), on: connection, then: then)
            return
        }
        let length = end - start + 1
        var fields = [
            "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")",
            "Content-Type: \(contentType)",
            "Content-Length: \(length)",
            // The player seeks: without ranges a seek is impossible, and the
            // car's video target asks for the bytes it wants.
            "Accept-Ranges: bytes",
            "Cache-Control: no-store"
        ]
        if range != nil {
            fields.append("Content-Range: bytes \(start)-\(end)/\(size)")
        }
        let header = fields.joined(separator: "\r\n") + "\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] _ in
            self?.sendFile(from: start, count: length, on: connection, then: then)
        })
    }

    /// Sends the bytes of the file — in pieces, so a long video is never held
    /// in memory.
    private func sendFile(from offset: Int, count: Int, on connection: NWConnection, then: @escaping () -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            connection.cancel()
            return
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
        } catch {
            handle.closeFile()
            connection.cancel()
            return
        }
        var remaining = count

        func pump() {
            guard remaining > 0 else {
                handle.closeFile()
                then()
                return
            }
            let data = handle.readData(ofLength: min(remaining, 256 * 1024))
            guard !data.isEmpty else {
                handle.closeFile()
                connection.cancel()
                return
            }
            remaining -= data.count
            connection.send(content: data, completion: .contentProcessed { _ in pump() })
        }
        pump()
    }

    private func send(status: String, type: String, body: Data, on connection: NWConnection, then: @escaping () -> Void) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.send(content: body, completion: .contentProcessed { _ in
                then()
            })
        })
    }

    /// "Range: bytes=0-1023" or "Range: bytes=1024-" → the bytes asked for.
    private static func parseRange(_ header: String) -> ClosedRange<Int>? {
        let value = header.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        let spec = value.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2, let first = Int(bounds[0]), first >= 0 else { return nil }
        if bounds[1].isEmpty { return first...Int.max }
        guard let last = Int(bounds[1]), last >= first else { return nil }
        return first...last
    }

    /// The token: 32 bytes from the system's random source, in hex.
    private static func makeToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares two strings without saying how much of them matched.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "m4a", "aac": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }
}

/// The port the listener was bound to — handed from the server's queue to the
/// caller that waits for it.
private final class BoundPort {
    private let lock = NSLock()
    private var value: UInt16?

    func set(_ new: UInt16?) {
        lock.lock()
        value = new
        lock.unlock()
    }

    func get() -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
