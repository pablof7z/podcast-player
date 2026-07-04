import Foundation

// ─── Per-domain push-frame envelope structs ───────────────────────────────
//
// Each app-owned `podcast.*` typed projection is decoded through the generated
// TypedProjectionDecoders + hand-written TypedProjectionGlue seam into one of
// these structs.
//
// CONTRACT (from MEMORY: FFI decode snake_case contract, PR #371):
//   - NO explicit CodingKeys enums on any type in this file.
//   - The bridge decoder uses `.convertFromSnakeCase`; explicit snake_case keys
//     override the strategy and cause `keyNotFound`, dropping the entire frame.
//   - All Rust snake_case field names map automatically to camelCase via the
//     decoder strategy: `now_playing` → `nowPlaying`, `inbox_triage_in_progress`
//     → `inboxTriageInProgress`, etc.
//   - Each envelope carries a `rev` field (monotonically increasing per-domain
//     counter) used by the drop-guard in KernelModel.
//   - TOMBSTONE: a domain may arrive as `{"rev":N,"<field>":null}` (cleared
//     slice). Decoding uses `decodeIfPresent` throughout so a null payload
//     produces a nil field rather than a decode error — the consumer clears
//     its slice when a field it relies on arrives nil.
//
// Source domains (from apps/nmp-app-podcast/read-projections.json and
// apps/nmp-app-podcast/src/ffi/snapshot_domain_projections.rs):
//   podcast.library   — library, categories, search_results, nostr_results,
//                       owned_podcasts, inbox, inbox_triage_in_progress,
//                       inbox_last_triaged_at
//   podcast.playback  — now_playing, queue
//   podcast.downloads — downloads (may arrive nil = no active downloads)
//   podcast.settings  — settings, configured_relays
//   podcast.identity  — active_account (may arrive nil = logged out)
//   podcast.widget    — widget (may arrive nil = nothing to show)
//   podcast.social    — social, nostr_conversations
//   podcast.voice     — voice (may arrive nil = idle/default state)
//   podcast.misc      — picks, agent_tasks, knowledge_search_results, memory_facts,
//                       clips, comments, agent, agent_context,
//                       feedback_events, feedback_threads

// ─── Schema IDs ──────────────────────────────────────────────────────────────

enum DomainSchema {
    static let library   = "podcast.library"
    static let playback  = "podcast.playback"
    static let downloads = "podcast.downloads"
    static let settings  = "podcast.settings"
    static let identity  = "podcast.identity"
    static let widget    = "podcast.widget"
    static let social    = "podcast.social"
    static let voice     = "podcast.voice"
    static let misc      = "podcast.misc"
}

// ─── podcast.library ─────────────────────────────────────────────────────────

struct LibraryDomainFrame: Decodable {
    var rev: UInt64 = 0
    var library: [PodcastSummary]?
    var categories: [CategoryBrowseItem]?
    var searchResults: [PodcastSummary]?
    var nostrResults: [NostrShowSummary]?
    var ownedPodcasts: [OwnedPodcastInfo]?
    var inbox: [InboxItem]?
    var inboxTriageInProgress: Bool?
    var inboxLastTriagedAt: Int?
}

// ─── podcast.playback ─────────────────────────────────────────────────────────

struct PlaybackDomainFrame: Decodable {
    var rev: UInt64 = 0
    var nowPlaying: PlayerState?
    var queue: [EpisodeSummary]?
}

// ─── podcast.downloads ───────────────────────────────────────────────────────

struct DownloadsDomainFrame: Decodable {
    var rev: UInt64 = 0
    /// `nil` when the kernel omits the field (no active downloads — tombstone
    /// or empty state). Distinct from the frame being absent: if the frame
    /// arrives but `downloads` is null, clear the download slice.
    var downloads: DownloadQueueSnapshot?
}

// ─── podcast.settings ────────────────────────────────────────────────────────

struct SettingsDomainFrame: Decodable {
    var rev: UInt64 = 0
    var settings: SettingsSnapshot?
    var configuredRelays: [AppRelayRow]?
}

// ─── podcast.identity ────────────────────────────────────────────────────────

struct IdentityDomainFrame: Decodable {
    var rev: UInt64 = 0
    /// `nil` when the kernel omits the field (no active account — tombstone /
    /// logged-out state). The consumer clears the identity slice when nil.
    var activeAccount: AccountSummary?
}

// ─── podcast.widget ──────────────────────────────────────────────────────────

struct WidgetDomainFrame: Decodable {
    var rev: UInt64 = 0
    var widget: WidgetSnapshot?
}

// ─── podcast.social ──────────────────────────────────────────────────────────

/// Social domain push frame: NIP-02 follow graph, flat agent-note feed, and
/// NIP-10-threaded Nostr conversations (merged inbound + outbound turns).
///
/// CONTRACT: NO explicit CodingKeys — the bridge decoder uses `.convertFromSnakeCase`.
/// `social: nil` arriving in this frame signals a tombstone (account switch
/// cleared all social state); consumers should clear their social slice.
struct SocialDomainFrame: Decodable {
    var rev: UInt64 = 0
    /// NIP-02 follow-list snapshot. `nil` = tombstone (cleared after account switch).
    var social: SocialSnapshot?
    /// NIP-10-threaded conversations, newest-first by lastActivity.
    /// Authoritative source for the `NostrConversationsView`.
    var nostrConversations: [NostrConversationDTO]?
    /// User-curated friends projected by Rust-owned FriendsState.
    /// `nil` means the key was absent from an older/test fixture payload; an
    /// emitted empty array is authoritative and clears the Swift friend slice.
    var friends: [FriendSummary]?
}

// ─── podcast.voice ───────────────────────────────────────────────────────────

struct VoiceDomainFrame: Decodable {
    var rev: UInt64 = 0
    /// `nil` when the kernel omits the field (voice idle/default state — tombstone).
    var voice: VoiceSnapshot?
}

// ─── podcast.misc ─────────────────────────────────────────────────────────────

struct MiscDomainFrame: Decodable {
    var rev: UInt64 = 0
    var picks: [AgentPickSummary]?
    var agentTasks: [AgentTaskSummary]?
    var knowledgeSearchResults: [KnowledgeSearchResult]?
    var memoryFacts: [MemoryFact]?
    var clips: [ClipSummary]?
    // social moved to SocialDomainFrame (podcast.social); flat agent_notes retired.
    // voice moved to VoiceDomainFrame (podcast.voice).
    var comments: [CommentSummary]?
    var agent: AgentSnapshot?
    var agentContext: AgentContextSnapshot?
    var feedbackEvents: [FeedbackEventDTO]?
    var feedbackThreads: [FeedbackThreadDTO]?
}

// ─── Composite push-frame result ─────────────────────────────────────────────

/// All per-domain frames extracted from one push frame. Only the domains that
/// were actually present in the frame (delta-changed since last emit) carry a
/// non-nil value. Absent domains MUST NOT overwrite the last-accepted state.
struct PodcastDomainFrames {
    var library:   LibraryDomainFrame?
    var playback:  PlaybackDomainFrame?
    var downloads: DownloadsDomainFrame?
    var settings:  SettingsDomainFrame?
    var identity:  IdentityDomainFrame?
    var widget:    WidgetDomainFrame?
    var social:    SocialDomainFrame?
    var voice:     VoiceDomainFrame?
    var misc:      MiscDomainFrame?
    /// Top-level `projections["resolved_profiles"]` map — NOT a `podcast.*`
    /// domain sidecar. The kernel emits this whenever a claimed pubkey resolves
    /// to a kind:0 profile. Empty when no profiles resolved this tick.
    /// Decoded via `.convertFromSnakeCase`; `ResolvedProfile` has no explicit
    /// CodingKeys so snake_case wire keys map cleanly to camelCase properties.
    var resolvedProfiles: [String: ResolvedProfile] = [:]

    /// `true` when at least one app domain or additive top-level projection was present.
    var hasAnyDomain: Bool {
        library != nil || playback != nil || downloads != nil ||
        settings != nil || identity != nil || widget != nil ||
        social != nil || voice != nil || misc != nil ||
        !resolvedProfiles.isEmpty
    }
}

// ─── PodcastDomainFrames helpers ─────────────────────────────────────────────

extension PodcastDomainFrames {
    /// Comma-joined list of domain names present in this frame (for logging).
    func presentDomainNames() -> String {
        var names: [String] = []
        if library   != nil { names.append("library") }
        if playback  != nil { names.append("playback") }
        if downloads != nil { names.append("downloads") }
        if settings  != nil { names.append("settings") }
        if identity  != nil { names.append("identity") }
        if widget    != nil { names.append("widget") }
        if social    != nil { names.append("social") }
        if voice     != nil { names.append("voice") }
        if misc      != nil { names.append("misc") }
        if !resolvedProfiles.isEmpty { names.append("resolved_profiles(\(resolvedProfiles.count))") }
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }
}

// ─── Decode helpers ──────────────────────────────────────────────────────────

extension PodcastDomainFrames {
    static func decode(from projections: [TypedProjectionEnvelope]) -> PodcastDomainFrames? {
        var frames = PodcastDomainFrames()

        frames.library   = TypedLibraryDecoder.decode(from: projections)
        frames.playback  = TypedPlaybackDecoder.decode(from: projections)
        frames.downloads = TypedDownloadsDecoder.decode(from: projections)
        frames.settings  = TypedSettingsDecoder.decode(from: projections)
        frames.identity  = TypedIdentityDecoder.decode(from: projections)
        frames.widget    = TypedWidgetDecoder.decode(from: projections)
        frames.social    = TypedSocialDecoder.decode(from: projections)
        frames.voice     = TypedVoiceDecoder.decode(from: projections)
        frames.misc      = TypedMiscDecoder.decode(from: projections)

        guard frames.hasAnyDomain else { return nil }
        return frames
    }

    static func decodeResolvedProfiles(from data: Data) -> [String: ResolvedProfile] {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = raw["v"] as? [String: Any],
            let projections = value["projections"] as? [String: Any]
        else { return [:] }

        // `resolved_profiles` is a TOP-LEVEL projections key (sibling of the
        // `podcast.*` domain sidecars, not nested inside one). Decode it with
        // the same `.convertFromSnakeCase` decoder used for all domain frames.
        // `ResolvedProfile` has NO explicit CodingKeys — wire `display_name` →
        // `displayName`, `picture_url` → `pictureUrl` via the strategy.
        // D6: any decode failure yields an empty map, never a frame drop.
        if let profilesObj = projections["resolved_profiles"],
           let profilesData = try? JSONSerialization.data(withJSONObject: profilesObj),
           let decoded = try? KernelDecoding.makeDecoder()
            .decode([String: ResolvedProfile].self, from: profilesData) {
            return decoded
        }

        return [:]
    }
}
