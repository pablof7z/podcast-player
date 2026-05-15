import Foundation

enum NIP65Publisher {
    static func buildTags(from configs: [RelayConfig]) -> [[String]] {
        configs.compactMap { config in
            guard config.read || config.write else { return nil }
            if config.read && config.write {
                return ["r", config.url]
            } else if config.read {
                return ["r", config.url, "read"]
            } else {
                return ["r", config.url, "write"]
            }
        }
    }

    static func buildDraft(from configs: [RelayConfig]) -> NostrEventDraft {
        NostrEventDraft(
            kind: 10002,
            content: "",
            tags: buildTags(from: configs)
        )
    }

    /// Publish kind:10002 to write relays + mirror to purplepag.es so other clients can discover it.
    static func publish(configs: [RelayConfig], signer: NostrSigner) async throws {
        let draft = buildDraft(from: configs)
        let signed = try await signer.sign(draft)

        var targetURLs = Set(configs.filter(\.write).map(\.url))
        targetURLs.insert(RelayConfig.normalizeURL("wss://purplepag.es"))

        let publisher = NostrWebSocketEventPublisher()
        await withTaskGroup(of: Void.self) { group in
            for urlString in targetURLs {
                guard let url = URL(string: urlString) else { continue }
                group.addTask {
                    try? await publisher.publish(event: signed, relayURL: url)
                }
            }
        }
    }
}
