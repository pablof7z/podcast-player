import Foundation

// MARK: - AgentOwnedPodcastManagerProtocol
//
// Manages agent-created synthetic podcasts: creation, metadata updates, artwork
// generation (via image-gen + Blossom upload), and NIP-F4 Nostr publishing.
// Implemented by `LiveAgentOwnedPodcastManager`, injected via `PodcastAgentToolDeps`.

protocol AgentOwnedPodcastManagerProtocol: Sendable {
    /// Create a new agent-owned synthetic podcast. The caller's Nostr pubkey
    /// is stamped as `ownerPubkeyHex`. Returns the podcast row's stable info.
    func createPodcast(
        title: String,
        description: String,
        author: String,
        imageURL: URL?,
        language: String?,
        categories: [String],
        visibility: Podcast.NostrVisibility
    ) async throws -> AgentOwnedPodcastInfo

    /// Update mutable metadata on an existing agent-owned podcast. Nil params
    /// keep the current value. If the podcast is public and nostr is enabled
    /// the updated kind:10154 event is re-published.
    func updatePodcast(
        podcastID: PodcastID,
        title: String?,
        description: String?,
        author: String?,
        imageURL: URL?,
        visibility: Podcast.NostrVisibility?
    ) async throws -> AgentOwnedPodcastInfo

    /// Delete an agent-owned podcast and all its episodes.
    func deletePodcast(podcastID: PodcastID) async throws

    /// All podcasts owned by this agent (ownerPubkeyHex is set), newest first.
    func listOwnedPodcasts() async -> [AgentOwnedPodcastInfo]

    /// Generate an image from `prompt`, upload it to Blossom, and return the
    /// resulting URL. The caller can then pass it to `createPodcast` /
    /// `updatePodcast` as `imageURL`.
    func generateAndUploadArtwork(prompt: String) async throws -> URL

    /// Upload the episode's audio, chapters, and transcript to Blossom, then
    /// publish a NIP-F4 kind:54 episode event signed by the podcast's own key.
    /// No-ops when nostr is disabled or the parent podcast is not agent-owned /
    /// is private. Returns the event ID of the published episode, or `nil` when
    /// the publish was skipped (disabled / private).
    func publishEpisodeToNostr(episodeID: EpisodeID) async throws -> String?
}

// MARK: - Result types

struct AgentOwnedPodcastInfo: Sendable {
    let podcastID: String
    let title: String
    let description: String
    let author: String
    let imageURL: URL?
    let visibility: String
    let episodeCount: Int
    /// Nostr event ID (32-byte hex) of the most recently published show event, if any.
    let nostrEventID: String?
    /// NIP-19 `npub` bech32 string for the podcast's own pubkey, if Nostr is enabled.
    let nostrAddr: String?
    /// Number of existing episodes published to Nostr during a batch operation
    /// (e.g. when a podcast's visibility flips to public). Nil when not applicable.
    let episodesPublishedToNostr: Int?
}
