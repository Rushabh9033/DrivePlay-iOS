import Foundation
import Network

/// The app's end of the relay channel.
///
/// The broadcast extension encodes the phone's screen and serves it; it cannot
/// hand the address of that server to the app any other way — the two live in
/// different processes and share no container (an App Group would need another
/// Apple-granted capability). So the extension opens a connection to this
/// listener and sends the address in one line.
///
/// The listener is bound to the loopback interface, so nothing outside the
/// phone can reach it.
final class ScreenRelayListener {

    /// Called with the address of the extension's stream.
    var onStream: ((_ port: UInt16, _ token: String) -> Void)?
    /// Called when the listener cannot listen — the port is taken, or the
    /// system refuses the bind. Without it the app would wait for an
    /// announcement that can never arrive, with nothing to show for it.
    var onFailure: ((Error) -> Void)?

    private let queue = DispatchQueue(label: "com.rushabh.cartvv.screenrelay.listener")
    /// The most bytes an announcement may take. The line carries a port and a
    /// token — a few dozen bytes — so 4 KB is generous.
    static let maximumAnnouncementLength = 4096
    private var listener: NWListener?
    /// The port the app listens on. The default is the one the broadcast
    /// extension announces to; a different one is only used to prove that a
    /// listener which cannot bind says so.
    private let port: UInt16

    init(port: UInt16 = ScreenRelayEndpoint.port) {
        self.port = port
    }

    /// Starts listening. Starting an already running listener does nothing —
    /// a restart would drop the announcement that is on its way.
    func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            NSLog("DRIVEPLAY screen relay: the listener failed: %@", error.localizedDescription)
            self?.onFailure?(error)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()

        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, isComplete, error in
                guard let self else {
                    connection.cancel()
                    return
                }
                guard error == nil, let data else {
                    connection.cancel()
                    return
                }
                buffer.append(data)
                // The line can arrive in pieces. A partial read is not a bad
                // line — it is half an address, and the extension does not send
                // it again, so the announcement has to be waited for.
                let text = String(decoding: buffer, as: UTF8.self)
                if let newline = text.firstIndex(of: "\n") {
                    let line = String(text[text.startIndex..<newline])
                    if let announced = ScreenRelayEndpoint.parse(line) {
                        self.onStream?(announced.port, announced.token)
                    }
                    connection.cancel()
                    return
                }
                // The announcement is one short line. A peer that keeps
                // sending without ever sending a newline must not be able to
                // grow the buffer without end.
                guard buffer.count <= Self.maximumAnnouncementLength else {
                    NSLog("DRIVEPLAY screen relay: the announcement grew past %d bytes — dropped", Self.maximumAnnouncementLength)
                    connection.cancel()
                    return
                }
                guard !isComplete else {
                    connection.cancel()
                    return
                }
                pump()
            }
        }
        pump()
    }
}
