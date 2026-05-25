import Foundation
import os.log

// MARK: - NostrPodcastPublisher
//
// Publishes NIP-F4 podcast events. Each podcast has its own keypair: the show
// metadata (kind:10154) and episodes (kind:54) are signed by the podcast key,
// while the owner agent periodically publishes a kind:10064 claim listing the
// podcast pubkeys it controls.
//
// Audio, chapters, and transcripts must be uploaded to Blossom before calling
// `publishEpisode` — the caller passes the resulting URLs; this service only
// handles event construction and relay publishing.
//
// Events are published concurrently to all `relayURLs`. Success requires at
// least one relay to acknowledge; individual failures are logged but not thrown.

struct NostrPodcastPublisher: Sendable {

    private static let logger = Logger.app("NostrPodcastPublisher")

    let publisher: any NostrEventPublishing
    let relayURLs: [URL]

    // MARK: - Publish show (kind:10154)

    /// Publish (or replace) the NIP-F4 show event for an agent-owned podcast.
    /// Returns the signed Nostr event ID (32-byte hex).
    @discardableResult
    func publishShow(podcast: Podcast, signer: any NostrSigner) async throws -> String {
        var tags: [[String]] = [
            ["title", podcast.title],
            ["p", try await signer.publicKey()],
        ]
        if !podcast.description.isEmpty {
            tags.append(["description", podcast.description])
        }
        if !podcast.author.isEmpty {
            tags.append(["author", podcast.author])
        }
        if let image = podcast.imageURL {
            tags.append(["image", image.absoluteString])
        }
        if let lang = podcast.language, !lang.isEmpty {
            tags.append(["language", lang])
        }
        for category in podcast.categories {
            tags.append(["t", category])
        }
        let draft = NostrEventDraft(kind: 10154, content: podcast.description, tags: tags)
        let signed = try await signer.sign(draft)
        try await publishToAll(event: signed)
        return signed.id
    }

    // MARK: - Publish episode (kind:54)

    /// Publish the NIP-F4 episode event.
    /// Returns the signed Nostr event ID (32-byte hex).
    ///
    /// - Parameters:
    ///   - episode: The episode to publish.
    ///   - podcast: The owning podcast.
    ///   - audioURL: Blossom URL of the uploaded audio file.
    ///   - chaptersURL: Optional Blossom URL of the uploaded chapters JSON.
    ///   - transcriptURL: Optional Blossom URL of the uploaded transcript.
    @discardableResult
    func publishEpisode(
        episode: Episode,
        podcast: Podcast,
        audioURL: URL,
        audioData: Data,
        chaptersURL: URL? = nil,
        transcriptURL: URL? = nil,
        signer: any NostrSigner
    ) async throws -> String {
        var tags: [[String]] = [
            ["title", episode.title],
            ["audio", audioURL.absoluteString, episode.enclosureMimeType ?? "audio/mp4"],
        ]

        if !episode.description.isEmpty {
            tags.append(["description", episode.description])
        }
        if let dur = episode.duration {
            tags.append(["duration", String(Int(dur))])
        }
        if let image = episode.imageURL ?? podcast.imageURL {
            tags.append(["image", image.absoluteString])
        }

        if let chaptersURL {
            tags.append(["chapters", chaptersURL.absoluteString, "application/json+chapters"])
        }
        if let transcriptURL {
            tags.append(["transcript", transcriptURL.absoluteString, "text/vtt"])
        }

        let draft = NostrEventDraft(kind: 54, content: episode.description, tags: tags)
        let signed = try await signer.sign(draft)
        try await publishToAll(event: signed)
        return signed.id
    }

    // MARK: - Publish author claim (kind:10064)

    /// Publish the agent's replaceable claim listing podcast pubkeys it owns.
    @discardableResult
    func publishAuthorClaim(podcastPubkeys: [String], agentSigner: any NostrSigner) async throws -> String {
        let tags = podcastPubkeys
            .filter { !$0.isEmpty }
            .sorted()
            .map { ["p", $0] }
        let draft = NostrEventDraft(kind: 10064, content: "", tags: tags)
        let signed = try await agentSigner.sign(draft)
        try await publishToAll(event: signed)
        return signed.id
    }

    // MARK: - Multi-relay publish

    /// Publishes `event` to all configured relay URLs concurrently.
    /// Succeeds if at least one relay acknowledges; throws if all fail.
    private func publishToAll(event: SignedNostrEvent) async throws {
        guard !relayURLs.isEmpty else {
            throw NostrEventPublisherError.noRelayConfigured
        }
        var lastError: Error?
        var anySuccess = false

        await withTaskGroup(of: (URL, Error?).self) { group in
            for url in relayURLs {
                group.addTask {
                    do {
                        try await self.publisher.publish(event: event, relayURL: url)
                        return (url, nil)
                    } catch {
                        return (url, error)
                    }
                }
            }
            for await (url, error) in group {
                if let error {
                    Self.logger.warning("Relay \(url.host ?? url.absoluteString, privacy: .public) rejected event \(event.id.prefix(8), privacy: .public): \(error.localizedDescription, privacy: .public)")
                    lastError = error
                } else {
                    Self.logger.info("Published \(event.id.prefix(8), privacy: .public) → \(url.host ?? url.absoluteString, privacy: .public)")
                    anySuccess = true
                }
            }
        }

        if !anySuccess, let lastError {
            throw lastError
        }
    }
}
