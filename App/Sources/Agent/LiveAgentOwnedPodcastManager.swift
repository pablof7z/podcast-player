import CryptoKit
import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - LiveAgentOwnedPodcastManager
//
// Production implementation of `AgentOwnedPodcastManagerProtocol`. Owns the
// full lifecycle: store mutations, image generation, Blossom uploads, and
// NIP-F4 event publishing. Constructed once per `AgentChatSession` via
// `LivePodcastAgentToolDeps.make(...)`.
//
// NIP-F4 keypair model: each podcast has its own Nostr key stored in
// PodcastKeyStore. podcast.ownerPubkeyHex holds the PODCAST's pubkey (not
// the agent's). The agent publishes kind:10064 to claim authorship.

final class LiveAgentOwnedPodcastManager: AgentOwnedPodcastManagerProtocol, @unchecked Sendable {

    private static let logger = Logger.app("AgentOwnedPodcastManager")

    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    // MARK: - Helpers

    @MainActor
    private func settings() -> Settings? { store?.state.settings }

    nonisolated private func agentSigner() throws -> LocalKeySigner {
        guard let hex = try NostrCredentialStore.privateKey(), !hex.isEmpty else {
            throw AgentOwnedPodcastError.noSigningKey
        }
        return try LocalKeySigner(privateKeyHex: hex)
    }

    nonisolated private func agentPubkeyHex() throws -> String {
        guard let hex = try NostrCredentialStore.privateKey(), !hex.isEmpty else {
            throw AgentOwnedPodcastError.noSigningKey
        }
        return try Crypto.getPublicKey(from: hex)
    }

    /// Returns the podcast's own signer, generating and persisting a key if needed.
    nonisolated private func podcastSigner(for podcastID: UUID) throws -> LocalKeySigner {
        if let existing = try PodcastKeyStore.privateKey(podcastID: podcastID), !existing.isEmpty {
            return try LocalKeySigner(privateKeyHex: existing)
        }
        let generated = try NDKPrivateKeySigner.generate()
        let privHex = generated.privateKeyForNIP59
        try PodcastKeyStore.savePrivateKey(privHex, podcastID: podcastID)
        return try LocalKeySigner(privateKeyHex: privHex)
    }

    nonisolated private func podcastPubkeyHex(for podcastID: UUID) throws -> String {
        if let existing = try PodcastKeyStore.privateKey(podcastID: podcastID), !existing.isEmpty {
            return try Crypto.getPublicKey(from: existing)
        }
        let generated = try NDKPrivateKeySigner.generate()
        let privHex = generated.privateKeyForNIP59
        try PodcastKeyStore.savePrivateKey(privHex, podcastID: podcastID)
        return try Crypto.getPublicKey(from: privHex)
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
        // For private podcasts, use the agent pubkey as a stable owner marker.
        // For public podcasts, generate/retrieve the podcast's own keypair and use its pubkey.
        let pubkey: String
        if visibility == .public {
            // Create a placeholder podcast first so we have a stable UUID for PodcastKeyStore.
            let placeholder = Podcast(
                kind: .synthetic,
                feedURL: nil,
                title: title,
                author: author,
                imageURL: imageURL,
                description: description,
                language: language,
                categories: categories,
                ownerPubkeyHex: (try? agentPubkeyHex()) ?? "pending",
                nostrVisibility: visibility
            )
            let stored0 = await MainActor.run { store?.upsertPodcast(placeholder) ?? placeholder }
            pubkey = (try? podcastPubkeyHex(for: stored0.id)) ?? (try? agentPubkeyHex()) ?? "pending"
            var updated = stored0
            updated.ownerPubkeyHex = pubkey
            await MainActor.run { store?.updatePodcast(updated) }
            Self.logger.info("Created agent-owned podcast '\(title, privacy: .public)' id=\(stored0.id, privacy: .public)")
            var showEventID: String?
            if let settings = await settings(), settings.nostrEnabled {
                showEventID = try? await publishShowEvent(podcast: updated, settings: settings)
            }
            let npub = nostrAddr(for: updated)
            return await MainActor.run { info(for: updated, nostrEventID: showEventID, nostrAddr: npub) }
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
        let npub = nostrAddr(for: stored)
        return await MainActor.run { info(for: stored, nostrEventID: nil, nostrAddr: npub) }
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

        // When flipping to public, ensure the podcast has its own keypair and pubkey set.
        if updated.nostrVisibility == .public && updated.ownerPubkeyHex == existing.ownerPubkeyHex && wasPrivate {
            if let podcastPubkey = try? podcastPubkeyHex(for: uuid) {
                updated.ownerPubkeyHex = podcastPubkey
                await MainActor.run { store?.updatePodcast(updated) }
            }
        }

        var showEventID: String?
        var episodesPublished: Int?
        if updated.nostrVisibility == .public, let settings = await settings(), settings.nostrEnabled {
            showEventID = try? await publishShowEvent(podcast: updated, settings: settings)
            // Retroactively publish all existing episodes when flipping to public.
            if wasPrivate {
                let episodes = await store?.episodes(forPodcast: uuid) ?? []
                var published = 0
                for episode in episodes {
                    do {
                        try await publishEpisodeRecord(episode, podcast: updated, settings: settings)
                        published += 1
                    } catch {
                        Self.logger.warning("Failed to publish episode '\(episode.title, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    }
                }
                episodesPublished = published
                Self.logger.info("Batch-published \(published)/\(episodes.count) episodes for '\(updated.title, privacy: .public)'")
            }
        }
        let npub = nostrAddr(for: updated)
        return await MainActor.run {
            info(for: updated, nostrEventID: showEventID, nostrAddr: npub, episodesPublishedToNostr: episodesPublished)
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
        try? PodcastKeyStore.deletePrivateKey(podcastID: uuid)
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
        let signer = try agentSigner()
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

        let eventID = try await publishEpisodeRecord(episode, podcast: podcast, settings: settings)
        Self.logger.info("Published episode '\(episode.title, privacy: .public)' to Nostr NIP-F4")
        return eventID
    }

    // MARK: - Private helpers

    /// Resolves the effective public relay list: stored list if non-empty, else defaults.
    nonisolated private func effectivePublicRelays(settings: Settings) -> [String] {
        let stored = settings.nostrPublicRelays.filter { !$0.isEmpty }
        return stored.isEmpty ? NIP65RelayFetcher.defaultRelays : stored
    }

    /// Publishes the NIP-F4 show kind:10154 event (signed by podcast key) and returns the event ID.
    /// Also refreshes the agent's kind:10064 author claim to include this podcast.
    @discardableResult
    nonisolated private func publishShowEvent(podcast: Podcast, settings: Settings) async throws -> String {
        let relayURLs = effectivePublicRelays(settings: settings).compactMap { URL(string: $0) }
        guard !relayURLs.isEmpty else {
            throw AgentOwnedPodcastError.noRelayConfigured
        }
        let podcastSigner = try podcastSigner(for: podcast.id)
        let publisher = NostrPodcastPublisher(relayURLs: relayURLs)
        let eventID = try await publisher.publishShow(podcast: podcast, signer: podcastSigner)

        // Update the agent's author claim to include all owned podcast pubkeys.
        if let agentSig = try? agentSigner(), let store {
            let allPodcasts = await store.allPodcasts.filter { $0.ownerPubkeyHex != nil && $0.nostrVisibility == .public }
            let pubkeys = allPodcasts.compactMap { $0.ownerPubkeyHex }
            if !pubkeys.isEmpty {
                _ = try? await publisher.publishAuthorClaim(podcastPubkeys: pubkeys, agentSigner: agentSig)
            }
        }

        return eventID
    }

    /// Uploads audio/chapters/transcript and publishes kind:54. Returns event ID.
    @discardableResult
    nonisolated private func publishEpisodeRecord(
        _ episode: Episode,
        podcast: Podcast,
        settings: Settings
    ) async throws -> String {
        let relayURLs = effectivePublicRelays(settings: settings).compactMap { URL(string: $0) }
        guard !relayURLs.isEmpty else {
            throw AgentOwnedPodcastError.noRelayConfigured
        }
        let podcastSig = try podcastSigner(for: podcast.id)
        let blossom = BlossomUploader(serverURLString: settings.blossomServerURL)
        let publisher = NostrPodcastPublisher(relayURLs: relayURLs)

        // Upload audio — Blossom auth signed by the podcast key.
        let audioData: Data
        if case .downloaded(let localURL, _) = episode.downloadState {
            do {
                audioData = try Data(contentsOf: localURL)
            } catch {
                Self.logger.error("publishEpisodeRecord: cannot read audio for '\(episode.title, privacy: .public)' at \(localURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                audioData = Data()
            }
        } else {
            audioData = Data()
        }
        let mimeType = episode.enclosureMimeType ?? "audio/mp4"
        let audioBlossomURL: URL
        if !audioData.isEmpty {
            audioBlossomURL = try await blossom.upload(data: audioData, contentType: mimeType, signer: podcastSig)
        } else {
            // Only use the enclosure URL directly when it is a remote (HTTP/HTTPS) URL —
            // for example, an RSS episode not yet downloaded. A local file:// URL must
            // never appear in a published Nostr event.
            let scheme = episode.enclosureURL.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" else {
                throw AgentOwnedPodcastError.audioNotAvailable(episode.title)
            }
            audioBlossomURL = episode.enclosureURL
        }

        // Upload chapters JSON if available.
        var chaptersBlossomURL: URL?
        if let chaptersData = serializeChapters(episode.chapters) {
            chaptersBlossomURL = try? await blossom.upload(data: chaptersData, contentType: "application/json", signer: podcastSig)
        } else if let chaptersURL = episode.chaptersURL,
                  let chaptersData = try? Data(contentsOf: chaptersURL) {
            chaptersBlossomURL = try? await blossom.upload(data: chaptersData, contentType: "application/json", signer: podcastSig)
        }

        // Upload transcript if available.
        var transcriptBlossomURL: URL?
        if case .ready = episode.transcriptState,
           let transcriptData = loadTranscriptData(episodeID: episode.id) {
            transcriptBlossomURL = try? await blossom.upload(data: transcriptData, contentType: "text/vtt", signer: podcastSig)
        }

        return try await publisher.publishEpisode(
            episode: episode,
            audioURL: audioBlossomURL,
            mimeType: mimeType,
            chaptersURL: chaptersBlossomURL,
            transcriptURL: transcriptBlossomURL,
            signer: podcastSig
        )
    }

    /// Returns the podcast's npub (NIP-19 bech32 public key) for sharing.
    nonisolated private func nostrAddr(for podcast: Podcast) -> String? {
        guard let pubkeyHex = podcast.ownerPubkeyHex else { return nil }
        return NIP19.npub(pubkeyHex: pubkeyHex)
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

    nonisolated private func loadTranscriptData(episodeID: UUID) -> Data? {
        guard let transcript = TranscriptStore.shared.load(episodeID: episodeID) else { return nil }
        var vtt = "WEBVTT\n\n"
        for (i, seg) in transcript.segments.enumerated() {
            vtt += "\(i + 1)\n"
            vtt += "\(formatVTTTime(seg.start)) --> \(formatVTTTime(seg.end))\n"
            vtt += "\(seg.text)\n\n"
        }
        return vtt.data(using: .utf8)
    }

    nonisolated private func serializeChapters(_ chapters: [Episode.Chapter]?) -> Data? {
        guard let chapters, !chapters.isEmpty else { return nil }
        let rows = chapters.map { ch -> [String: Any] in
            var row: [String: Any] = ["startTime": ch.startTime, "title": ch.title]
            if let url = ch.linkURL { row["url"] = url.absoluteString }
            if let img = ch.imageURL { row["img"] = img.absoluteString }
            return row
        }
        let json: [String: Any] = ["version": "1.2.0", "chapters": rows]
        return try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    }

    nonisolated private func formatVTTTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

enum AgentOwnedPodcastError: LocalizedError {
    case storeUnavailable
    case noSigningKey
    case noRelayConfigured
    case invalidID(String)
    case notFound(String)
    case notOwned(String)
    case episodeNotFound(String)
    case audioNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: return "App state is unavailable."
        case .noSigningKey: return "No Nostr signing key configured. Set up your identity in Settings > Agent > Identity."
        case .noRelayConfigured: return "No Nostr relay configured. Set a relay URL in Settings > Agent > Nostr."
        case .invalidID(let id): return "Invalid UUID: \(id)"
        case .notFound(let id): return "Podcast not found: \(id)"
        case .notOwned(let id): return "Podcast \(id) is not agent-owned."
        case .episodeNotFound(let id): return "Episode not found: \(id)"
        case .audioNotAvailable(let title): return "Audio file for '\(title)' could not be read for upload."
        }
    }
}
