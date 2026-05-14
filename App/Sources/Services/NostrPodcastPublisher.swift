import CryptoKit
import Foundation

// MARK: - NostrPodcastPublisher
//
// Publishes NIP-74 (kind:30074 podcast show, kind:30075 podcast episode) addressable
// events signed by the agent's key. Both kinds are parameterised replaceable events
// (NIP-33): each `d` tag uniquely identifies the show / episode across updates.
//
// Audio, chapters, and transcripts must be uploaded to Blossom before calling
// `publishEpisode` — the caller passes the resulting URLs; this service only
// handles event construction and relay publishing.

struct NostrPodcastPublisher: Sendable {

    let publisher: any NostrEventPublishing
    let relayURL: URL

    // MARK: - Publish show (kind:30074)

    /// Publish (or replace) the NIP-74 show event for an agent-owned podcast.
    func publishShow(podcast: Podcast, signer: any NostrSigner) async throws {
        var tags: [[String]] = [
            ["d", "podcast:guid:\(podcast.id.uuidString.lowercased())"],
            ["title", podcast.title],
        ]
        if !podcast.description.isEmpty {
            tags.append(["summary", podcast.description])
        }
        if !podcast.author.isEmpty {
            tags.append(["p", try await signer.publicKey()])
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
        let draft = NostrEventDraft(kind: 30074, content: podcast.description, tags: tags)
        let signed = try await signer.sign(draft)
        try await publisher.publish(event: signed, relayURL: relayURL)
    }

    // MARK: - Publish episode (kind:30075)

    /// Publish (or replace) the NIP-74 episode event.
    ///
    /// - Parameters:
    ///   - episode: The episode to publish.
    ///   - podcast: The owning podcast (must have an `ownerPubkeyHex`).
    ///   - audioURL: Blossom URL of the uploaded audio file.
    ///   - audioData: Raw audio bytes — used to compute the `x` (SHA-256) hash for `imeta`.
    ///   - chaptersURL: Optional Blossom URL of the uploaded chapters JSON.
    ///   - transcriptURL: Optional Blossom URL of the uploaded transcript.
    func publishEpisode(
        episode: Episode,
        podcast: Podcast,
        audioURL: URL,
        audioData: Data,
        chaptersURL: URL? = nil,
        transcriptURL: URL? = nil,
        signer: any NostrSigner
    ) async throws {
        let pubkey = try await signer.publicKey()
        let showDTag = "podcast:guid:\(podcast.id.uuidString.lowercased())"
        let audioHash = Data(SHA256.hash(data: audioData)).hexString
        let pubDateSeconds = String(Int(episode.pubDate.timeIntervalSince1970))

        var tags: [[String]] = [
            ["d", "podcast:item:guid:\(episode.id.uuidString.lowercased())"],
            ["title", episode.title],
            ["published_at", pubDateSeconds],
            ["a", "30074:\(pubkey):\(showDTag)"],
        ]

        if !episode.description.isEmpty {
            tags.append(["summary", episode.description])
        }
        if let dur = episode.duration {
            tags.append(["duration", String(Int(dur))])
        }
        if let image = episode.imageURL ?? podcast.imageURL {
            tags.append(["image", image.absoluteString])
        }

        var imetaParts = [
            "url \(audioURL.absoluteString)",
            "m audio/mp4",
            "x \(audioHash)",
            "size \(audioData.count)",
        ]
        if let dur = episode.duration { imetaParts.append("duration \(Int(dur))") }
        tags.append(["imeta"] + imetaParts)

        if let chaptersURL {
            tags.append(["chapters", chaptersURL.absoluteString, "application/json+chapters"])
        }
        if let transcriptURL {
            tags.append(["transcript", transcriptURL.absoluteString, "text/vtt"])
        }

        let draft = NostrEventDraft(kind: 30075, content: episode.description, tags: tags)
        let signed = try await signer.sign(draft)
        try await publisher.publish(event: signed, relayURL: relayURL)
    }
}

