import Foundation

enum RelayDefaults {
    static let seedRelays: [RelayConfig] = [
        RelayConfig(url: "wss://relay.tenex.chat", read: true, write: true, rooms: true),
        RelayConfig(url: "wss://relay.damus.io", read: true, write: true),
        RelayConfig(url: "wss://purplepag.es", indexer: true),
        RelayConfig(url: "wss://relay.primal.net", indexer: true),
    ]

    struct PinnedRelay {
        let url: String
        let minRead: Bool
        let minWrite: Bool
        let minRooms: Bool
        let minIndexer: Bool
    }

    static let pinnedRelays: [PinnedRelay] = [
        PinnedRelay(url: "wss://relay.tenex.chat", minRead: true, minWrite: false, minRooms: false, minIndexer: false),
        PinnedRelay(url: "wss://purplepag.es", minRead: false, minWrite: false, minRooms: false, minIndexer: true),
    ]

    static func enforcePinnedInvariants(_ relays: inout [RelayConfig]) {
        for pinned in pinnedRelays {
            let normalizedURL = RelayConfig.normalizeURL(pinned.url)
            if let idx = relays.firstIndex(where: { $0.url == normalizedURL }) {
                if pinned.minRead { relays[idx].read = true }
                if pinned.minWrite { relays[idx].write = true }
                if pinned.minRooms { relays[idx].rooms = true }
                if pinned.minIndexer { relays[idx].indexer = true }
            } else {
                relays.append(RelayConfig(
                    url: pinned.url,
                    read: pinned.minRead,
                    write: pinned.minWrite,
                    rooms: pinned.minRooms,
                    indexer: pinned.minIndexer
                ))
            }
        }
    }
}
