import Foundation

enum RelayConfigMerger {
    struct NIP65Entry {
        let url: String
        let read: Bool
        let write: Bool
    }

    struct NIP78Entry {
        let url: String
        let rooms: Bool
        let indexer: Bool
    }

    static func merge(nip65: [NIP65Entry], nip78: [NIP78Entry]) -> [RelayConfig] {
        if nip65.isEmpty && nip78.isEmpty {
            return RelayDefaults.seedRelays
        }

        var configsByURL: [String: RelayConfig] = [:]

        // Layer 1: NIP-65 entries (read/write) — OR flags for duplicate tags
        // since a valid kind:10002 may include separate ["r", url, "read"] and ["r", url, "write"] tags.
        for entry in nip65 {
            let url = RelayConfig.normalizeURL(entry.url)
            if var existing = configsByURL[url] {
                existing.read = existing.read || entry.read
                existing.write = existing.write || entry.write
                configsByURL[url] = existing
            } else {
                configsByURL[url] = RelayConfig(url: url, read: entry.read, write: entry.write)
            }
        }

        for entry in nip78 {
            let url = RelayConfig.normalizeURL(entry.url)
            if var existing = configsByURL[url] {
                existing.rooms = entry.rooms
                existing.indexer = entry.indexer
                configsByURL[url] = existing
            } else {
                configsByURL[url] = RelayConfig(url: url, rooms: entry.rooms, indexer: entry.indexer)
            }
        }

        var result = Array(configsByURL.values)
        RelayDefaults.enforcePinnedInvariants(&result)
        return result.sorted { $0.url < $1.url }
    }

    /// Parse kind:10002 event tags into NIP65 entries.
    /// Per NIP-65: `["r", url]` = both read+write; `["r", url, "read"]` = read-only; `["r", url, "write"]` = write-only.
    static func parseNIP65(tags: [[String]]) -> [NIP65Entry] {
        tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == "r" else { return nil }
            let url = tag[1]
            if tag.count >= 3 {
                switch tag[2] {
                case "read": return NIP65Entry(url: url, read: true, write: false)
                case "write": return NIP65Entry(url: url, read: false, write: true)
                default: return NIP65Entry(url: url, read: true, write: true)
                }
            }
            return NIP65Entry(url: url, read: true, write: true)
        }
    }

    static func parseNIP78(content: String) -> [NIP78Entry] {
        guard let data = content.data(using: .utf8) else { return [] }
        struct Entry: Codable { var url: String; var rooms: Bool?; var indexer: Bool? }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map { NIP78Entry(url: $0.url, rooms: $0.rooms ?? false, indexer: $0.indexer ?? false) }
    }
}
