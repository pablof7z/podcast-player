import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrPodcastPublisher
//
// Publishes NIP-F4 Nostr podcast events:
//   kind:10154 — podcast show (replaceable, no d-tag; show == podcast keypair)
//   kind:54    — podcast episode (regular event; authored by podcast key)
//   kind:10064 — agent author claim (replaceable; agent key lists owned podcast pubkeys)
//
// Each podcast has its own Nostr keypair (see PodcastKeyStore). The signer
// passed to publishShow/publishEpisode is the PODCAST's signer, not the agent's.
// publishAuthorClaim takes the AGENT's signer.
//
// Audio, chapters, and transcripts must be uploaded to Blossom before calling
// publishEpisode — the caller passes the resulting URLs.

struct NostrPodcastPublisher: Sendable {

    private static let logger = Logger.app("NostrPodcastPublisher")

    let relayURLs: [URL]

    // MARK: - Publish show (kind:10154)

    /// Publish (or replace) the NIP-F4 show event for a podcast.
    /// Signed by the podcast's own key. Returns the signed event ID.
    @discardableResult
    func publishShow(podcast: Podcast, signer: any NostrSigner) async throws -> String {
        let pubkey = try await signer.publicKey()

        var tags: [[String]] = [
            ["title", podcast.title],
        ]
        if !podcast.description.isEmpty {
            tags.append(["description", podcast.description])
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
        if !podcast.author.isEmpty {
            tags.append(["p", pubkey, "host"])
        }

        let draft = NostrEventDraft(kind: 10154, content: "", tags: tags)
        let signed = try await signer.sign(draft)
        try await publishViaNDK(event: signed)
        return signed.id
    }

    // MARK: - Publish episode (kind:54)

    /// Publish a NIP-F4 episode event. Signed by the podcast's own key.
    /// Returns the signed event ID.
    @discardableResult
    func publishEpisode(
        episode: Episode,
        audioURL: URL,
        mimeType: String = "audio/mp4",
        chaptersURL: URL? = nil,
        transcriptURL: URL? = nil,
        signer: any NostrSigner
    ) async throws -> String {
        var tags: [[String]] = [
            ["title", episode.title],
            ["audio", audioURL.absoluteString, mimeType],
        ]
        if !episode.description.isEmpty {
            tags.append(["description", episode.description])
        }
        if let dur = episode.duration {
            tags.append(["duration", String(Int(dur))])
        }
        if let image = episode.imageURL {
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
        try await publishViaNDK(event: signed)
        return signed.id
    }

    // MARK: - Publish author claim (kind:10064)

    /// Publish (or replace) the agent's NIP-F4 author claim listing all podcast pubkeys.
    /// Signed by the AGENT's key (not the podcast key).
    @discardableResult
    func publishAuthorClaim(podcastPubkeys: [String], agentSigner: any NostrSigner) async throws -> String {
        let tags = podcastPubkeys.map { ["p", $0] }
        let draft = NostrEventDraft(kind: 10064, content: "", tags: tags)
        let signed = try await agentSigner.sign(draft)
        try await publishViaNDK(event: signed)
        return signed.id
    }

    // MARK: - NDK publish

    private func publishViaNDK(event: SignedNostrEvent) async throws {
        guard let ndk = await NostrStack.shared.ndk else {
            throw NostrEventPublisherError.noRelayConfigured
        }

        let targetSet: Set<String>? = relayURLs.isEmpty
            ? nil
            : Set(relayURLs.map { $0.absoluteString })

        do {
            let accepted = try await ndk.publish(NDKEventConverter.toNDKEvent(event), to: targetSet)
            if accepted.isEmpty {
                Self.logger.warning("Published \(event.id.prefix(8), privacy: .public) kind=\(event.kind) — no relay accepted (queued or no outbox)")
                throw NostrEventPublisherError.noRelayConfigured
            }
            let names = accepted.map { $0.url }.sorted().joined(separator: ", ")
            Self.logger.info("Published \(event.id.prefix(8), privacy: .public) kind=\(event.kind) → \(names, privacy: .public)")
        } catch let error as NostrEventPublisherError {
            throw error
        } catch {
            Self.logger.warning("Publish failed for \(event.id.prefix(8), privacy: .public) kind=\(event.kind): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
