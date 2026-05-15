import CryptoKit
import Foundation
import os.log

// MARK: - NostrPodcastPublisher
//
// Publishes NIP-74 (kind:30074 podcast show, kind:30075 podcast episode)
// addressable events. With the Rust core in place, all event construction,
// signing, and multi-relay broadcast are owned by Rust — this struct now
// only translates Swift-side `Podcast` / `Episode` values into FFI args and
// returns the resulting Nostr event id.
//
// The `publisher` and `relayURLs` properties are retained for source
// compatibility with existing call sites (`LiveAgentOwnedPodcastManager`)
// but the Rust pool ignores them: writes go to the entire configured
// outbox set.

struct NostrPodcastPublisher: Sendable {

    private static let logger = Logger.app("NostrPodcastPublisher")

    // rust-cutover: retained for source-compat with existing callers; Rust
    // pool owns the actual relay fan-out and signing.
    let publisher: any NostrEventPublishing
    let relayURLs: [URL]

    // MARK: - Publish show (kind:30074)

    /// Publish (or replace) the NIP-74 show event for an agent-owned podcast.
    /// Returns the signed Nostr event ID (32-byte hex).
    @discardableResult
    @MainActor
    func publishShow(podcast: Podcast, signer _: any NostrSigner) async throws -> String {
        // rust-cutover: signer ignored; Rust core uses the configured signer.
        let dTag = "podcast:guid:\(podcast.id.uuidString.lowercased())"
        do {
            let signed = try await PodcastrCoreBridge.shared.core.publishPodcastShow(
                dTag: dTag,
                title: podcast.title,
                author: podcast.author,
                description: podcast.description,
                imageUrl: podcast.imageURL?.absoluteString,
                categories: podcast.categories
            )
            Self.logger.info("Published show \(signed.id.prefix(8), privacy: .public) via Rust pool")
            return signed.id
        } catch {
            throw NostrEventPublisherError.rejected(error.localizedDescription)
        }
    }

    // MARK: - Publish episode (kind:30075)

    /// Publish (or replace) the NIP-74 episode event.
    /// Returns the signed Nostr event ID (32-byte hex).
    @discardableResult
    @MainActor
    func publishEpisode(
        episode: Episode,
        podcast: Podcast,
        audioURL: URL,
        audioData: Data,
        chaptersURL: URL? = nil,
        transcriptURL: URL? = nil,
        signer _: any NostrSigner
    ) async throws -> String {
        // rust-cutover: signer ignored; Rust core uses the configured signer.
        // The show coordinate is rebuilt from the *current* Rust pubkey rather
        // than from the legacy signer arg — they must match for the `a`-tag
        // pointer to resolve back to a show this user actually owns.
        guard let pubkey = PodcastrCoreBridge.shared.core.currentPubkey() else {
            throw NostrEventPublisherError.noSigningKey
        }
        let showDTag = "podcast:guid:\(podcast.id.uuidString.lowercased())"
        let showCoordinate = "30074:\(pubkey):\(showDTag)"
        let episodeDTag = "podcast:item:guid:\(episode.id.uuidString.lowercased())"
        let audioHashHex = Data(SHA256.hash(data: audioData)).hexString
        // `TimeInterval` is Double — clamp to non-negative before narrowing
        // to UInt64 so a malformed feed can't trap on the cast.
        let durationU64: UInt64? = episode.duration.map { UInt64(max(0, $0)) }

        do {
            let signed = try await PodcastrCoreBridge.shared.core.publishPodcastEpisode(
                dTag: episodeDTag,
                showCoordinate: showCoordinate,
                title: episode.title,
                description: episode.description,
                audioUrl: audioURL.absoluteString,
                mimeType: "audio/mp4",
                sha256Hex: audioHashHex,
                size: UInt64(audioData.count),
                duration: durationU64,
                chaptersUrl: chaptersURL?.absoluteString,
                transcriptUrl: transcriptURL?.absoluteString
            )
            Self.logger.info("Published episode \(signed.id.prefix(8), privacy: .public) via Rust pool")
            return signed.id
        } catch {
            throw NostrEventPublisherError.rejected(error.localizedDescription)
        }
    }
}
