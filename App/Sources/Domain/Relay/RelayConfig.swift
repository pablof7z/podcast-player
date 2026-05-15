import Foundation

struct RelayConfig: Codable, Hashable, Identifiable, Sendable {
    var url: String
    var read: Bool = false
    var write: Bool = false
    var rooms: Bool = false
    var indexer: Bool = false

    var id: String { url }
    var hasAnyRole: Bool { read || write || rooms || indexer }

    init(url: String, read: Bool = false, write: Bool = false, rooms: Bool = false, indexer: Bool = false) {
        self.url = Self.normalizeURL(url)
        self.read = read
        self.write = write
        self.rooms = rooms
        self.indexer = indexer
    }

    static func normalizeURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        var result = components.string ?? raw
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
