import Foundation

public struct M3UParser: Sendable {
    public init() {}
    
    public enum ParseError: LocalizedError {
        case invalidHeader
        case emptyContent
        case networkError(String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidHeader:
                return "Not a valid M3U playlist. File must start with #EXTM3U."
            case .emptyContent:
                return "The playlist content is empty."
            case .networkError(let msg):
                return "Failed to download playlist: \(msg)"
            }
        }
    }
    
    /// Parses M3U or M3U8 string content into an array of Channel models
    public func parse(content: String, sourceId: UUID = UUID()) throws -> [Channel] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.emptyContent
        }
        
        guard trimmed.hasPrefix("#EXTM3U") || trimmed.contains("#EXTINF") else {
            throw ParseError.invalidHeader
        }
        
        var channels: [Channel] = []
        var currentTvgId: String?
        var currentLogoURL: URL?
        var currentGroupTitle: String = "Other"
        var currentGroupIsExplicit = false
        var pendingGroupTitle: String?   // set by #EXTGRP, applies to the next entry
        var currentChannelName: String?
        var currentResolution: String = "HD"

        let lines = content.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                // Parse #EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="...", Channel Name
                let (attributes, name) = parseExtInfLine(line)
                currentChannelName = name
                currentTvgId = attributes["tvg-id"]

                if let logoStr = attributes["tvg-logo"], let url = URL(string: logoStr.trimmingCharacters(in: .whitespaces)) {
                    currentLogoURL = url
                } else {
                    currentLogoURL = nil
                }

                // Group comes from this entry's own tag, else a preceding #EXTGRP,
                // else the default. It must never be inherited from the previous entry.
                if let group = attributes["group-title"], !group.isEmpty {
                    currentGroupTitle = group
                    currentGroupIsExplicit = true
                } else {
                    currentGroupTitle = pendingGroupTitle ?? "Other"
                    currentGroupIsExplicit = false
                }
                pendingGroupTitle = nil

                // Derive resolution label from channel name
                currentResolution = detectResolution(from: name)

            } else if line.hasPrefix("#EXTGRP:") {
                let grp = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
                if !grp.isEmpty {
                    if currentChannelName != nil && !currentGroupIsExplicit {
                        // #EXTGRP trails the #EXTINF it belongs to.
                        currentGroupTitle = grp
                    } else {
                        pendingGroupTitle = grp
                    }
                }
            } else if !line.hasPrefix("#") {
                // This is the stream URL
                if let url = URL(string: line), let name = currentChannelName {
                    let channel = Channel(
                        id: UUID(),
                        name: name,
                        streamURL: url,
                        groupTitle: currentGroupTitle,
                        logoURL: currentLogoURL,
                        tvgId: currentTvgId,
                        sourceId: sourceId,
                        isFavorite: false,
                        isPlayable: true,
                        resolutionLabel: currentResolution
                    )
                    channels.append(channel)
                }

                // Reset temporary entry state
                currentTvgId = nil
                currentLogoURL = nil
                currentChannelName = nil
                currentResolution = "HD"
                currentGroupIsExplicit = false
                pendingGroupTitle = nil
            }
        }

        return channels
    }
    
    /// Parse key-value attributes and trailing title from #EXTINF line
    private func parseExtInfLine(_ line: String) -> (attributes: [String: String], name: String) {
        var attributes: [String: String] = [:]
        var name = "Unknown Channel"

        // Find the comma that separates the attributes from the title.
        // Quoted attribute values may themselves contain commas, so quotes are tracked:
        //   #EXTINF:-1 tvg-name="Movie, The",Movie, The
        // The separator is the comma after the closing quote, not the one inside it.
        if let commaIndex = findTitleSeparator(in: line) {
            let nameSubstr = line[line.index(after: commaIndex)...]
            name = nameSubstr.trimmingCharacters(in: .whitespaces)
            let attributesSubstr = line[..<commaIndex]

            // Regex to extract key="value" or key=value — a provider that does
            // not quote the value loses its tvg-id and its logo that way.
            let pattern = "([a-zA-Z0-9_-]+)=(?:\"([^\"]*)\"|([^\\s,]+))"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsStr = String(attributesSubstr) as NSString
                let matches = regex.matches(in: String(attributesSubstr), range: NSRange(location: 0, length: nsStr.length))
                for match in matches {
                    guard match.numberOfRanges >= 4 else { continue }
                    let key = nsStr.substring(with: match.range(at: 1)).lowercased()
                    let quoted = match.range(at: 2)
                    let bare = match.range(at: 3)
                    if quoted.location != NSNotFound {
                        attributes[key] = nsStr.substring(with: quoted)
                    } else if bare.location != NSNotFound {
                        attributes[key] = nsStr.substring(with: bare)
                    }
                }
            }
        } else {
            name = line.replacingOccurrences(of: "#EXTINF:", with: "").trimmingCharacters(in: .whitespaces)
        }

        return (attributes, name.isEmpty ? "Unknown Channel" : name)
    }

    /// Index of the comma that ends the attribute list and begins the channel title.
    /// Falls back to the first comma when the quoting is unbalanced.
    private func findTitleSeparator(in line: String) -> String.Index? {
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            switch line[index] {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                return index
            default:
                break
            }
            index = line.index(after: index)
        }
        return line.firstIndex(of: ",")
    }
    
    /// Smart resolution tag detection (4K HDR, 1080P, 720P, etc.)
    private func detectResolution(from name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("4K") && upper.contains("HDR") {
            return "4K HDR"
        } else if upper.contains("4K") || upper.contains("UHD") {
            return "4K"
        } else if upper.contains("1080P") && upper.contains("60") {
            return "1080P 60FPS"
        } else if upper.contains("1080P") && (upper.contains("H.264") || upper.contains("H264")) {
            return "1080P H.264"
        } else if upper.contains("1080P") || upper.contains("FHD") {
            return "1080P"
        } else if upper.contains("720P") {
            return "720P"
        } else if upper.contains("HD") {
            // The channel says "HD" — it does not say "720P", and the app must
            // not claim a resolution the provider never gave.
            return "HD"
        }
        return "1080P"
    }
}
