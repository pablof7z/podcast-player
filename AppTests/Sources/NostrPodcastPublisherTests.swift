import Foundation
import XCTest
@testable import Pod0

final class NostrPodcastPublisherTests: XCTestCase {
    func testPublishShowUsesNIPF4KindAndPodcastSigner() async throws {
        let capture = CapturingNostrPublisher()
        let publisher = NostrPodcastPublisher(
            publisher: capture,
            relayURLs: [URL(string: "wss://relay.example.com")!]
        )
        let signer = LocalKeySigner(keyPair: try NostrKeyPair.generate())
        let podcast = Podcast(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            kind: .synthetic,
            title: "Pod0 Daily",
            author: "Pod0",
            imageURL: URL(string: "https://example.com/art.png"),
            description: "A daily synthetic show.",
            language: "en",
            categories: ["technology"],
            ownerPubkeyHex: try await signer.publicKey(),
            nostrVisibility: .public
        )

        let eventID = try await publisher.publishShow(podcast: podcast, signer: signer)
        let events = await capture.events()
        let event = try XCTUnwrap(events.first)
        let signerPubkey = try await signer.publicKey()

        XCTAssertEqual(eventID, event.id)
        XCTAssertEqual(event.kind, 10154)
        XCTAssertEqual(event.pubkey, signerPubkey)
        XCTAssertEqual(event.tagValue("title"), "Pod0 Daily")
        XCTAssertEqual(event.tagValue("description"), "A daily synthetic show.")
        XCTAssertEqual(event.tagValue("author"), "Pod0")
        XCTAssertEqual(event.tagValue("p"), signerPubkey)
        XCTAssertFalse(event.hasTag("d"))
    }

    func testPublishEpisodeUsesNIPF4AudioTagAndNoNIP74Tags() async throws {
        let capture = CapturingNostrPublisher()
        let publisher = NostrPodcastPublisher(
            publisher: capture,
            relayURLs: [URL(string: "wss://relay.example.com")!]
        )
        let signer = LocalKeySigner(keyPair: try NostrKeyPair.generate())
        let podcast = Podcast(
            id: UUID(),
            kind: .synthetic,
            title: "Pod0 Daily",
            imageURL: URL(string: "https://example.com/show.png"),
            ownerPubkeyHex: try await signer.publicKey(),
            nostrVisibility: .public
        )
        let episode = Episode(
            podcastID: podcast.id,
            guid: "episode-guid",
            title: "Launch Notes",
            description: "What changed today.",
            pubDate: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 120,
            enclosureURL: URL(string: "https://example.com/audio.mp3")!,
            enclosureMimeType: "audio/mpeg"
        )

        try await publisher.publishEpisode(
            episode: episode,
            podcast: podcast,
            audioURL: URL(string: "https://cdn.example.com/audio.mp3")!,
            audioData: Data("audio".utf8),
            signer: signer
        )
        let events = await capture.events()
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.kind, 54)
        XCTAssertEqual(event.content, "What changed today.")
        XCTAssertEqual(event.tagValue("title"), "Launch Notes")
        XCTAssertEqual(event.tagValue("description"), "What changed today.")
        XCTAssertEqual(event.tagValue("duration"), "120")
        XCTAssertEqual(event.tags.first(where: { $0.first == "audio" }), [
            "audio", "https://cdn.example.com/audio.mp3", "audio/mpeg",
        ])
        XCTAssertFalse(event.hasTag("d"))
        XCTAssertFalse(event.hasTag("a"))
        XCTAssertFalse(event.hasTag("published_at"))
        XCTAssertFalse(event.hasTag("imeta"))
    }

    func testPublishAuthorClaimUsesAgentSignerAndPtags() async throws {
        let capture = CapturingNostrPublisher()
        let publisher = NostrPodcastPublisher(
            publisher: capture,
            relayURLs: [URL(string: "wss://relay.example.com")!]
        )
        let agentSigner = LocalKeySigner(keyPair: try NostrKeyPair.generate())
        let pubkeys = [
            String(repeating: "b", count: 64),
            String(repeating: "a", count: 64),
        ]

        try await publisher.publishAuthorClaim(podcastPubkeys: pubkeys, agentSigner: agentSigner)
        let events = await capture.events()
        let event = try XCTUnwrap(events.first)
        let agentPubkey = try await agentSigner.publicKey()

        XCTAssertEqual(event.kind, 10064)
        XCTAssertEqual(event.pubkey, agentPubkey)
        XCTAssertEqual(event.tags, [["p", pubkeys[1]], ["p", pubkeys[0]]])
    }
}

private actor CapturingNostrPublisher: NostrEventPublishing {
    private var publishedEvents: [SignedNostrEvent] = []

    func publish(event: SignedNostrEvent, relayURL: URL) async throws {
        publishedEvents.append(event)
    }

    func events() -> [SignedNostrEvent] {
        publishedEvents
    }
}

private extension SignedNostrEvent {
    func tagValue(_ name: String) -> String? {
        tags.first { $0.first == name }?[safe: 1]
    }

    func hasTag(_ name: String) -> Bool {
        tags.contains { $0.first == name }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
