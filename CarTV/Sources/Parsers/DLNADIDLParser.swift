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
    /// True while the parser is inside an `<item>`.
    ///
    /// The document also carries a `<dc:title>` for the **container** — the
    /// name of the folder the items live in. That is not the title of the
    /// first item, and it used to be glued onto it.
    private var isInsideItem = false

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
        isInsideItem = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return items.first
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            isInsideItem = true
            title = ""
            streamURLString = ""
            artworkURLString = ""
            duration = nil
            mimeType = nil
        }
        if currentElement == "res", isInsideItem {
            // An item may carry several `<res>` elements — one per protocol
            // and bitrate. Only the first one is the stream; the others would
            // be concatenated into an address that does not exist.
            guard streamURLString.isEmpty else { return }
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
        guard isInsideItem else { return }
        switch currentElement {
        case "dc:title", "title":
            title += string
        case "res":
            // Only the first `<res>` of an item is the stream — the others
            // would be concatenated into an address that does not exist.
            guard streamURLString.isEmpty else { return }
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
            isInsideItem = false
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
