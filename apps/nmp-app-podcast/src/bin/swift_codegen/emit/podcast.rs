// ─────────────────────────────────────────────────────────────────────────────
// PodcastTypes.generated.swift — legacy redirect stub
// ─────────────────────────────────────────────────────────────────────────────

pub(super) fn emit_podcast_types() -> String {
    r#"// PodcastTypes.generated.swift
// This file has been split into four focused files in the same directory:
//
//   PodcastUpdate.generated.swift      — PodcastUpdate, PlayerState,
//                                        AccountSummary, DownloadQueueSnapshot,
//                                        DownloadItemSnapshot
//   PodcastSettingsSnapshot.generated.swift
//                                      — SettingsSnapshot
//   PodcastLibraryTypes.generated.swift — PodcastSummary, EpisodeSummary, ChapterSummary,
//                                        TranscriptEntry, AdSegment, OwnedPodcastInfo,
//                                        NostrShowSummary
//   PodcastMediaTypes.generated.swift  — VoiceSnapshot, AgentSnapshot, AgentMessageSummary,
//                                        AgentTaskSummary, AgentPickSummary,
//                                        TtsEpisodeSummary, ClipSummary
//   PodcastSocialTypes.generated.swift — InboxItem, CommentSummary, ContactSummary,
//                                        SocialSnapshot, CategoryBrowseItem,
//                                        KnowledgeSearchResult, MemoryFact
//
// Intended regeneration command (once the dumper exists):
//
//   cargo run -p nmp-app-podcast --features codegen-schema \
//       --bin dump_projection_schemas \
//     | cargo run -p nmp-codegen -- gen swift
//
// Source of truth: apps/nmp-app-podcast/src/ffi/snapshot.rs
"#.to_string()
}

// ─────────────────────────────────────────────────────────────────────────────
// PodcastAgentContextTypes.generated.swift
// Source: ffi/projections/agent_context.rs
// ─────────────────────────────────────────────────────────────────────────────

pub(super) fn emit_agent_context_types() -> String {
    let hdr = "// PodcastAgentContextTypes.generated.swift\n\
// Hand-maintained mirror of the Rust agent-context projection types.\n\
// Split out of `PodcastUpdate.generated.swift` to keep that file under the\n\
// 500-line hard limit. Keep camelCase in sync with snake_case Rust source —\n\
// `.convertFromSnakeCase` handles the key mapping.\n\
// Source of truth: apps/nmp-app-podcast/src/ffi/projections/agent_context.rs\n\
\n\
import Foundation\n";

    let mut out = hdr.to_string();
    out += r#"
/// Agent-prompt inventory context. Mirrors
/// `ffi::projections::AgentContextSnapshot`. The kernel performs all
/// selection / ordering / capping; `AgentPrompt` only renders the strings.
struct AgentContextSnapshot: Equatable {
    /// Subscribed-show titles, already sorted + capped by the kernel.
    var subscriptions: [String] = []
    /// Followed-show count *before* the cap (drives the "(N)" header and the
    /// "…and N more" suffix).
    var subscriptionsTotal: Int = 0
    /// In-progress episodes (started, not finished, not archived), newest-first.
    var inProgress: [AgentContextEpisode] = []
    /// Recent unplayed episodes inside the recency window, newest-first.
    var recentUnplayed: [AgentContextEpisode] = []
    /// Recency-window width (days) the kernel applied to `recentUnplayed`.
    var recentWindowDays: Int = 0
}

/// One episode row in `AgentContextSnapshot`. Mirrors
/// `ffi::projections::AgentContextEpisode`. Carries the resolved show title
/// so the renderer needs no second lookup.
struct AgentContextEpisode: Equatable {
    var title: String = ""
    var showTitle: String = ""
}

// MARK: - Custom Decodable implementations
//
// Rust uses `#[serde(default, skip_serializing_if = "Vec::is_empty")]` on the
// collection fields (omit when empty). `decodeIfPresent` with explicit
// fallbacks keeps the decoder forward- and backward-compatible.

extension AgentContextSnapshot: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decodeIfPresent([String].self, forKey: .subscriptions) ?? []
        subscriptionsTotal = try c.decodeIfPresent(Int.self, forKey: .subscriptionsTotal) ?? 0
        inProgress = try c.decodeIfPresent([AgentContextEpisode].self, forKey: .inProgress) ?? []
        recentUnplayed = try c.decodeIfPresent([AgentContextEpisode].self, forKey: .recentUnplayed) ?? []
        recentWindowDays = try c.decodeIfPresent(Int.self, forKey: .recentWindowDays) ?? 0
    }
}

extension AgentContextEpisode: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        showTitle = try c.decodeIfPresent(String.self, forKey: .showTitle) ?? ""
    }
}
"#;
    out
}

// ─────────────────────────────────────────────────────────────────────────────
// PodcastDownloadTypes.generated.swift
// Source: ffi/projections/download.rs
// ─────────────────────────────────────────────────────────────────────────────

pub(super) fn emit_download_types() -> String {
    r#"// PodcastDownloadTypes.generated.swift
// Hand-maintained mirror of Rust projection types. See PodcastUpdate.generated.swift.

import Foundation

/// Active download-queue projection surfaced via `PodcastUpdate.downloads`.
struct DownloadQueueSnapshot: Equatable {
    var active: [DownloadItemSnapshot] = []
    var queuedCount: Int = 0
    var completedToday: Int = 0
}

/// One row in `DownloadQueueSnapshot.active`.
struct DownloadItemSnapshot: Identifiable, Equatable {
    var episodeId: String
    /// What this row fetches. Omitted on the wire for episodes (the default),
    /// so it must decode-default to `.episode`. Lets the model UI pick out its
    /// own rows and lets the episode overlay skip non-episode rows.
    var kind: DownloadKind = .episode
    var progress: Double = 0
    var state: String
    /// Total file size (bytes) once the server reports `Content-Length`.
    /// `nil` until the first HTTP response arrives.
    var totalBytes: Int64? = nil
    var error: String? = nil

    var id: String { episodeId }
}

extension DownloadQueueSnapshot: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decodeIfPresent([DownloadItemSnapshot].self, forKey: .active) ?? []
        queuedCount = try c.decodeIfPresent(Int.self, forKey: .queuedCount) ?? 0
        completedToday = try c.decodeIfPresent(Int.self, forKey: .completedToday) ?? 0
    }
}

extension DownloadItemSnapshot: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodeId = try c.decode(String.self, forKey: .episodeId)
        kind = try c.decodeIfPresent(DownloadKind.self, forKey: .kind) ?? .episode
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        state = try c.decode(String.self, forKey: .state)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}
"#.to_string()
}
