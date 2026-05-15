import CryptoKit
import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrPodcastPublisher
//
// Publishes NIP-74 (kind:30074 podcast show, kind:30075 podcast episode)
// addressable events signed by the agent's key. Both kinds are parameterised
// replaceable events (NIP-33): each `d` tag uniquely identifies the show /
// episode across updates.
//
// Audio, chapters, and transcripts must be uploaded to Blossom before calling
// `publishEpisode` — the caller passes the resulting URLs; this service only
// handles event construction and relay publishing.
//
// Migration note (NDKSwift): this struct used to fan out to a caller-supplied
// list of relay URLs over raw WebSockets. It now hands the signed event to
// the shared `NDK` instance owned by `NostrStack.shared`. `relayURLs` is
// still load-bearing — it's passed through to `ndk.publish(_:to:)` as the
// explicit target set, because Podcastr agent identities do not currently
// publish their own kind:10002 outbox list. The `publisher` init parameter
// is vestigial (NDK does the publishing) and can be dropped once
// `LiveAgentOwnedPodcastManager` is refactored.

struct NostrPodcastPublisher: Sendable {

    private static let logger = Logger.app("NostrPodcastPublisher")

    let publisher: any NostrEventPublishing
    let relayURLs: [URL]

    // MARK: - Publish show (kind:30074)

    /// Publish (or replace) the NIP-74 show event for an agent-owned podcast.
    /// Returns the signed Nostr event ID (32-byte hex).
    @discardableResult
    func publishShow(podcast: Podcast, signer: any NostrSigner) async throws -> String {
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
        try await publishViaNDK(event: signed)
        return signed.id
    }

    // MARK: - Publish episode (kind:30075)

    /// Publish (or replace) the NIP-74 episode event.
    /// Returns the signed Nostr event ID (32-byte hex).
    ///
    /// - Parameters:
    ///   - episode: The episode to publish.
    ///   - podcast: The owning podcast (must have an `ownerPubkeyHex`).
    ///   - audioURL: Blossom URL of the uploaded audio file.
    ///   - audioData: Raw audio bytes — used to compute the `x` (SHA-256) hash for `imeta`.
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
        try await publishViaNDK(event: signed)
        return signed.id
    }

    // MARK: - NDK publish

    /// Hands the signed event to the shared NDK instance and routes it to
    /// the caller-supplied `relayURLs`. We do not rely on NDK's NIP-65
    /// outbox routing here: Podcastr agent identities don't currently
    /// publish their own kind:10002, so a bare `ndk.publish(event)` would
    /// resolve to an empty relay set and the publish would queue forever.
    ///
    /// If `relayURLs` is empty we fall back to NDK's outbox routing as a
    /// best-effort path. The init parameter is load-bearing, not vestigial.
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
