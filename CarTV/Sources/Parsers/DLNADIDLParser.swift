import Foundation

public struct DLNADIDLItem: Sendable {
    public let title: String
    public let streamURL: URL
    public let artworkURL: URL?
    public let duration: String?
    public let mimeType: String?
}

public final class DLNADIDLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var currentElement: String = ""
    private var title: String = ""
    private var streamURLString: String = ""
    private var artworkURLString: String = ""
    private var duration: String?
    private var mimeType: String?
    private var items: [DLNADIDLItem] = []

    /// Returns the first playable item in the DIDL-Lite document.
    ///
    /// A DIDL-Lite browse response carries one `<item>` per media entry. Per-item
    /// state has to be reset at every `</item>`, otherwise the title and URL of every
    /// entry are concatenated into one garbled item.
    public func parse(xmlString: String) -> DLNADIDLItem? {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        title = ""
        streamURLString = ""
        artworkURLString = ""
        duration = nil
        mimeType = nil
        items = []

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return items.first
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "res" {
            duration = attributeDict["duration"]
            // protocolInfo is a DLNA options string ("http-get:*:video/mp4:DLNA.ORG_OP=04"),
            // not a MIME type — the MIME is its third colon-separated field.
            mimeType = attributeDict["protocolInfo"]?
                .split(separator: ":")
                .dropFirst(2)
                .first
                .map(String.init)
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "dc:title", "title":
            title += string
        case "res":
            streamURLString += string
        case "upnp:albumarturi", "albumarturi":
            artworkURLString += string
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "item" {
            if let url = URL(string: streamURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let artUrl = URL(string: artworkURLString.trimmingCharacters(in: .whitespacesAndNewlines))
                items.append(DLNADIDLItem(
                    title: title.isEmpty ? "Cast Media" : title.trimmingCharacters(in: .whitespacesAndNewlines),
                    streamURL: url,
                    artworkURL: artUrl,
                    duration: duration,
                    mimeType: mimeType
                ))
            }
            // Reset for the next item so entries don't bleed into each other.
            title = ""
            streamURLString = ""
            artworkURLString = ""
            duration = nil
            mimeType = nil
        }
        // Clear the current element so inter-element whitespace is not appended to
        // the text of the element that just closed.
        currentElement = ""
    }
}
