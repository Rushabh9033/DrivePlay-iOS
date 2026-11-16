#!/bin/sh
# Checks the vault's file server **without the phone**: the real source file is
# compiled for the Mac and answered over HTTP. The XCTest (AC176) needs a
# device; this one does not.
#
#   scripts/vault_server_check.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

let path = CommandLine.arguments[1]
let bytes = Data((0..<5000).map { UInt8($0 % 251) })
try bytes.write(to: URL(fileURLWithPath: path))

guard let server = VaultFileServer(fileURL: URL(fileURLWithPath: path)),
      let url = server.start() else { fatalError("the server did not start") }

var problems: [String] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if !ok { problems.append("\(name): \(detail)") }
    print("\(ok ? "ok  " : "FAIL") \(name) \(detail)")
}
func status(_ response: URLResponse?) -> Int { (response as? HTTPURLResponse)?.statusCode ?? -1 }
func header(_ response: URLResponse?, _ field: String) -> String? {
    (response as? HTTPURLResponse)?.value(forHTTPHeaderField: field)
}

let sem = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: url) { data, response, _ in
    check("200 for the whole file", status(response) == 200, "status \(status(response))")
    check("the bytes are the file", data == bytes, "\(data?.count ?? -1) bytes")
    check("the type is the file's", header(response, "Content-Type") == "video/mp4")
    check("ranges are offered", header(response, "Accept-Ranges") == "bytes")

    // The token: 32 bytes in hex, and the path carries it.
    // The path is "/<token>/<file>".
    let token = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
    check("the token is 32 bytes of hex", token.count == 64 && token.allSatisfy { $0.isHexDigit },
          "\(token.count) characters")

    var request = URLRequest(url: url)
    request.setValue("bytes=100-199", forHTTPHeaderField: "Range")
    URLSession.shared.dataTask(with: request) { slice, rangeResponse, _ in
        check("206 for a range", status(rangeResponse) == 206, "status \(status(rangeResponse))")
        check("the slice is right", slice == bytes[100..<200], "\(slice?.count ?? -1) bytes")
        check("the range is announced",
              header(rangeResponse, "Content-Range") == "bytes 100-199/5000",
              header(rangeResponse, "Content-Range") ?? "none")

        var open = URLRequest(url: url)
        open.setValue("bytes=4000-", forHTTPHeaderField: "Range")
        URLSession.shared.dataTask(with: open) { tail, tailResponse, _ in
            check("206 for an open range", status(tailResponse) == 206, "status \(status(tailResponse))")
            check("the tail is right", tail == bytes[4000...], "\(tail?.count ?? -1) bytes")

            let wrong = url.deletingLastPathComponent().appendingPathComponent("nope.mp4")
            URLSession.shared.dataTask(with: wrong) { _, wrongResponse, _ in
                check("404 without the token's path", status(wrongResponse) == 404,
                      "status \(status(wrongResponse))")

                // The token is the lock: a wrong one gets nothing.
                let wrongToken = url.deletingLastPathComponent()
                    .appendingPathComponent(String(repeating: "0", count: 64))
                    .appendingPathComponent(url.lastPathComponent)
                URLSession.shared.dataTask(with: wrongToken) { _, tokenResponse, _ in
                    check("404 with a wrong token", status(tokenResponse) == 404,
                          "status \(status(tokenResponse))")
                    sem.signal()
                }.resume()
            }.resume()
        }.resume()
    }.resume()
}.resume()

_ = sem.wait(timeout: .now() + 30)
server.stop()
print(problems.isEmpty ? "\nALL GREEN" : "\nPROBLEMS:\n" + problems.joined(separator: "\n"))
exit(problems.isEmpty ? 0 : 1)
SWIFT

swiftc -o "$WORK/check" "$ROOT/CarTV/Sources/Services/VaultFileServer.swift" "$WORK/main.swift"
"$WORK/check" "$WORK/sample.mp4"
