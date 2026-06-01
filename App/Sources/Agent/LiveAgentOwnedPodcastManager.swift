import Foundation
import os.log

// MARK: - LiveAgentOwnedPodcastManager
//
// Production implementation of `AgentOwnedPodcastManagerProtocol`. Owns the
// store mutations + artwork generation; all Nostr publishing is delegated to
// the Rust kernel via the `podcast.publish` NIP-F4 action namespace
// (kind:10154 show / kind:54 episode / kind:10064 author-claim). Constructed
// once per `AgentChatSession` via `LivePodcastAgentToolDeps.make(...)`.
//
// Publishing model (NIP-F4 — replaces the deleted Swift NIP-74 builders):
// Rust owns the cryptography. `create_owned_podcast` generates a per-podcast
// keypair and registers it; `publish_show` / `publish_episode` sign + broadcast
// against that key, uploading audio to Blossom Rust-side. The agent's own key
// no longer signs show/episode events. Dispatch is fire-and-forget — the signed
// event id / naddr lives in Rust's snapshot projection, not returned here.

final class LiveAgentOwnedPodcastManager: AgentOwnedPodcastManagerProtocol, @unchecked Sendable {

    private static let logger = Logger.app("AgentOwnedPodcastManager")

    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    // MARK: - Helpers

    @MainActor
    private func settings() -> Settings? { store?.state.settings }

    nonisolated private func nostrSigner() throws -> LocalKeySigner {
        guard let hex = try NostrCredentialStore.privateKey(), !hex.isEmpty else {
            throw AgentOwnedPodcastError.noSigningKey
        }
        let kp = try NostrKeyPair(privateKeyHex: hex)
        return LocalKeySigner(keyPair: kp)
    }

    nonisolated private func agentPubkeyHex() throws -> String {
        try nostrSigner().keyPair.publicKeyHex
    }

    // MARK: - createPodcast

    func createPodcast(
        title: String,
        description: String,
        author: String,
        imageURL: URL?,
        language: String?,
        categories: [String],
        visibility: Podcast.NostrVisibility
    ) async throws -> AgentOwnedPodcastInfo {
        let pubkey: String
        if visibility == .public {
            pubkey = try agentPubkeyHex()
        } else {
            pubkey = (try? agentPubkeyHex()) ?? "agent-private"
        }
        let podcast = Podcast(
            kind: .synthetic,
            feedURL: nil,
            title: title,
            author: author,
            imageURL: imageURL,
            description: description,
            language: language,
            categories: categories,
            ownerPubkeyHex: pubkey,
            nostrVisibility: visibility
        )
        let stored = await MainActor.run {
            store?.upsertPodcast(podcast) ?? podcast
        }
        Self.logger.info("Created agent-owned podcast '\(title, privacy: .public)' id=\(stored.id, privacy: .public)")
        // Claim the per-podcast NIP-F4 signing key once, at creation, regardless
        // of visibility — so a later private→public flip can publish without
        // rotating the key. Publishing the show event is gated on public+enabled.
        await claimOwnership(podcastID: stored.id)
        if visibility == .public, let settings = await settings(), settings.nostrEnabled {
            await publishShowToNostr(podcastID: stored.id)
        }
        return await MainActor.run { info(for: stored, nostrEventID: nil, nostrAddr: nil) }
    }

    // MARK: - updatePodcast

    func updatePodcast(
        podcastID: PodcastID,
        title: String?,
        description: String?,
        author: String?,
        imageURL: URL?,
        visibility: Podcast.NostrVisibility?
    ) async throws -> AgentOwnedPodcastInfo {
        guard let uuid = UUID(uuidString: podcastID) else {
            throw AgentOwnedPodcastError.invalidID(podcastID)
        }
        guard let existing = await store?.podcast(id: uuid) else {
            throw AgentOwnedPodcastError.notFound(podcastID)
        }
        guard existing.ownerPubkeyHex != nil else {
            throw AgentOwnedPodcastError.notOwned(podcastID)
        }
        let wasPrivate = existing.nostrVisibility != .public
        var updated = existing
        if let title { updated.title = title }
        if let description { updated.description = description }
        if let author { updated.author = author }
        if let imageURL { updated.imageURL = imageURL }
        if let visibility { updated.nostrVisibility = visibility }
        await MainActor.run { store?.updatePodcast(updated) }

        var episodesPublished: Int?
        if updated.nostrVisibility == .public, let settings = await settings(), settings.nostrEnabled {
            await publishShowToNostr(podcastID: uuid)
            // Retroactively publish all existing episodes when flipping to public.
            if wasPrivate {
                let episodes = await store?.episodes(forPodcast: uuid) ?? []
                for episode in episodes {
                    await dispatchPublishEpisode(episodeID: episode.id)
                }
                episodesPublished = episodes.count
                Self.logger.info("Dispatched NIP-F4 publish for \(episodes.count) episodes of '\(updated.title, privacy: .public)'")
            }
        }
        return await MainActor.run {
            info(for: updated, nostrEventID: nil, nostrAddr: nil, episodesPublishedToNostr: episodesPublished)
        }
    }

    // MARK: - deletePodcast

    func deletePodcast(podcastID: PodcastID) async throws {
        guard let uuid = UUID(uuidString: podcastID) else {
            throw AgentOwnedPodcastError.invalidID(podcastID)
        }
        guard let existing = await store?.podcast(id: uuid) else {
            throw AgentOwnedPodcastError.notFound(podcastID)
        }
        guard existing.ownerPubkeyHex != nil else {
            throw AgentOwnedPodcastError.notOwned(podcastID)
        }
        await MainActor.run {
            guard let store else { return }
            store.deletePodcast(podcastID: uuid)
        }
    }

    // MARK: - listOwnedPodcasts

    func listOwnedPodcasts() async -> [AgentOwnedPodcastInfo] {
        guard let store else { return [] }
        let podcasts = await store.allPodcasts.filter { $0.ownerPubkeyHex != nil }
        return await MainActor.run { podcasts.map { info(for: $0, nostrEventID: nil, nostrAddr: nil) } }
    }

    // MARK: - generateAndUploadArtwork

    func generateAndUploadArtwork(prompt: String) async throws -> URL {
        guard let settings = await settings() else {
            throw AgentOwnedPodcastError.storeUnavailable
        }
        guard settings.openRouterCredentialSource != .none,
              let apiKey = try? OpenRouterCredentialStore.apiKey(),
              !apiKey.isEmpty else {
            throw ImageGenerationError.noAPIKey
        }
        let imageGen = ImageGenerationService(apiKey: apiKey)
        let imageData = try await imageGen.generate(prompt: prompt, model: settings.imageGenerationModel)
        let signer = try nostrSigner()
        let blossom = BlossomUploader(serverURLString: settings.blossomServerURL)
        let url = try await blossom.upload(data: imageData, contentType: "image/png", signer: signer)
        Self.logger.info("Artwork uploaded to \(url.absoluteString, privacy: .public)")
        return url
    }

    // MARK: - publishEpisodeToNostr

    func publishEpisodeToNostr(episodeID: EpisodeID) async throws -> String? {
        guard let uuid = UUID(uuidString: episodeID),
              let store else { throw AgentOwnedPodcastError.storeUnavailable }
        guard let episode = await store.episode(id: uuid) else {
            throw AgentOwnedPodcastError.episodeNotFound(episodeID)
        }
        guard let podcast = await store.podcast(id: episode.podcastID),
              podcast.ownerPubkeyHex != nil,
              podcast.nostrVisibility == .public else { return nil }
        guard let settings = await settings(), settings.nostrEnabled else { return nil }

        await dispatchPublishEpisode(episodeID: uuid)
        Self.logger.info("Dispatched NIP-F4 publish for episode '\(episode.title, privacy: .public)'")
        // Dispatch is fire-and-forget; the signed event id / naddr now lives in
        // Rust's snapshot projection. Return a non-nil status marker so callers
        // (publish_episode tool) report success rather than a false "skipped".
        return "nipf4:publish_dispatched"
    }

    // MARK: - Private NIP-F4 dispatch helpers

    /// Claim ownership of the podcast: Rust generates the per-podcast signing
    /// key and stamps `owner_pubkey_hex`. MUST be called exactly once per
    /// podcast — `generate_key` overwrites unconditionally
    /// (`store/podcast_keys.rs::generate_key`), so a second call rotates the
    /// key, which would orphan the prior replaceable `kind:10154` show event
    /// (keyed by pubkey) rather than replace it. Only the *first* claim per
    /// podcast may run.
    private func claimOwnership(podcastID: UUID) async {
        let id = podcastID.uuidString
        await MainActor.run { store?.kernelCreateOwnedPodcast(podcastId: id) }
    }

    /// Publish (or replace) the `kind:10154` show event for an already-claimed
    /// podcast. Does NOT re-claim — see `claimOwnership` for why re-claiming is
    /// destructive.
    private func publishShowToNostr(podcastID: UUID) async {
        let id = podcastID.uuidString
        await MainActor.run { store?.kernelPublishShow(podcastId: id) }
    }

    /// Publish the `kind:54` episode event. Rust resolves the parent podcast +
    /// its per-podcast key and uploads audio to Blossom.
    private func dispatchPublishEpisode(episodeID: UUID) async {
        let id = episodeID.uuidString
        await MainActor.run {
            store?.kernelPublishEpisode(episodeId: id)
        }
    }

    @MainActor
    private func info(
        for podcast: Podcast,
        nostrEventID: String?,
        nostrAddr: String?,
        episodesPublishedToNostr: Int? = nil
    ) -> AgentOwnedPodcastInfo {
        let episodeCount = (store?.episodes(forPodcast: podcast.id) ?? []).count
        return AgentOwnedPodcastInfo(
            podcastID: podcast.id.uuidString,
            title: podcast.title,
            description: podcast.description,
            author: podcast.author,
            imageURL: podcast.imageURL,
            visibility: podcast.nostrVisibility.rawValue,
            episodeCount: episodeCount,
            nostrEventID: nostrEventID,
            nostrAddr: nostrAddr,
            episodesPublishedToNostr: episodesPublishedToNostr
        )
    }
}

enum AgentOwnedPodcastError: LocalizedError {
    case storeUnavailable
    case noSigningKey
    case invalidID(String)
    case notFound(String)
    case notOwned(String)
    case episodeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: return "App state is unavailable."
        case .noSigningKey: return "No Nostr signing key configured. Set up your identity in Settings > Agent > Identity."
        case .invalidID(let id): return "Invalid UUID: \(id)"
        case .notFound(let id): return "Podcast not found: \(id)"
        case .notOwned(let id): return "Podcast \(id) is not agent-owned."
        case .episodeNotFound(let id): return "Episode not found: \(id)"
        }
    }
}
