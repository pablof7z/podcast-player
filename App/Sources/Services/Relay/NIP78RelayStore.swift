import Foundation

enum NIP78RelayStore {
    static let dTag = "com.podcast.relays"

    struct Entry: Codable {
        var url: String
        var rooms: Bool
        var indexer: Bool
    }

    static func buildDraft(from configs: [RelayConfig]) -> NostrEventDraft? {
        let entries = configs
            .filter { $0.rooms || $0.indexer }
            .map { Entry(url: $0.url, rooms: $0.rooms, indexer: $0.indexer) }

        guard !entries.isEmpty else { return nil }

        guard let data = try? JSONEncoder().encode(entries),
              let content = String(data: data, encoding: .utf8) else { return nil }

        return NostrEventDraft(
            kind: 30078,
            content: content,
            tags: [["d", dTag]]
        )
    }

    static func publish(configs: [RelayConfig], signer: NostrSigner) async throws {
        guard let draft = buildDraft(from: configs) else { return }
        let signed = try await signer.sign(draft)

        let writeURLs = configs.filter(\.write).map(\.url)
        let publisher = NostrWebSocketEventPublisher()
        await withTaskGroup(of: Void.self) { group in
            for urlString in writeURLs {
                guard let url = URL(string: urlString) else { continue }
                group.addTask {
                    try? await publisher.publish(event: signed, relayURL: url)
                }
            }
        }
    }
}
