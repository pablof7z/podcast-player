# Snapshot schema — `PodcastUpdate`

The kernel emits a single JSON snapshot on every tick. Swift decodes
into `PodcastUpdate` (Decodable). View modules inside Rust own the
precomputed shape so Swift never derives.

Rust source of truth: `apps/podcast/nmp-app-podcast/src/snapshot.rs`.

## D5 — bounded by what's open

When a view is closed, its slot is `null`. Episode lists for
non-selected podcasts are not serialized. Wiki pages not currently
open are not serialized. The full library catalog is paginated.
Audit each field against D5 when adding.

## Top-level shape (TypeScript-ish for readability)

```ts
type PodcastUpdate = {
  running: boolean
  rev: u64
  schema_version: u32              // bump on incompatible change

  // Identity
  active_account?: AccountSummary
  accounts: AccountSummary[]
  nip46_onboarding: Nip46OnboardingState
  bunker_handshake: BunkerHandshakeState

  // Library
  podcasts: PodcastSummary[]
  selected_podcast?: PodcastDetail
  episodes_for_selected: EpisodeSummary[]      // windowed
  today_queue: EpisodeSummary[]
  recents: EpisodeSummary[]
  triage: TriageProjection
  categories: PodcastCategory[]
  library: LibrarySnapshot                     // filter+search projection
  library_display: LibraryDisplayProjection    // precomputed accent/symbol/% (M2)

  // Discovery
  discover: DiscoverProjection
  nostr_podcast_feed: NostrPodcastFeedSummary[]

  // Playback
  now_playing?: NowPlayingState
  downloads: DownloadStatus[]

  // Transcripts (D5 — only open episode)
  transcription_queue: TranscriptionJob[]
  transcript_for_open_episode?: TranscriptView

  // Knowledge (D5 — only open page)
  wiki_index: WikiIndexEntry[]
  wiki_page?: WikiPageView
  rag_search_result?: RagSearchResult

  // Agent
  agent_chat: AgentChatProjection
  agent_chat_streaming?: AgentStreamingTokens  // ≈30 Hz (if NMP supports)
  agent_run_log: AgentRunLogEntry[]
  scheduled_tasks: AgentScheduledTask[]
  briefings: BriefingProjection
  picks: AgentPicksProjection
  inbox_triage: InboxTriageProjection
  pending_ask?: AskRequest

  // Voice (D5 — only when voice mode active)
  voice_session?: VoiceSessionProjection

  // Nostr social
  friends: FriendSummary[]
  nostr_conversations: ConversationSummary[]
  pending_approvals: PendingApproval[]
  publish_outbox: PublishQueueEntry[]
  outbox_summary: OutboxSummary

  // Feedback (M10 — new feature surface)
  feedback: FeedbackProjection

  // Settings
  settings: SettingsView
  byok_status: BYOKStatus
  cost_ledger: CostLedgerSummary

  // Relays
  relay_status: { [url: string]: RelayStatus }
  relay_edit_rows: RelayEditRow[]
  recent_routing_decisions: RoutingDecisionLog

  // Capability mirror (diagnostic)
  capability_requests: CapabilityRequestLog

  // Action lifecycle
  action_lifecycle: ActionLifecycle

  // Platform integrations (iOS-only fields; null elsewhere)
  car_play?: CarPlayState
  live_activity?: LiveActivityState
  handoff?: HandoffActivity

  // What's new
  whats_new: WhatsNewProjection

  // Toasts
  toasts: Toast[]
}
```

## Mapping to legacy `AppState`

| Current `AppState.*` | New `PodcastUpdate.*` |
|---|---|
| `subscriptions` | `podcasts[]` (subscription info inline) |
| `episodes` | `episodes_for_selected`, `recents`, `today_queue` |
| `notes` | held in Rust; surfaced under open agent chat / open wiki |
| `friends` | `friends[]` |
| `agentMemories` | `agent_run_log`, `agent_chat.context_summary` |
| `scheduledTasks` | `scheduled_tasks[]` |
| `nostrConversations` | `nostr_conversations[]` |
| `pendingApprovals` | `pending_approvals[]` |
| `clips` | held in Rust; surfaced under `episodes_for_selected[].clips` when expanded |
| `categories` | `categories[]` |
| `settings` | `settings` |
| `adSegments` | inline in `EpisodeSummary.ad_segments` |
| Player state (`PlaybackState.swift`) | `now_playing`, `player` projection |
| `BriefingComposer` state | `briefings` |
| `RAGService` state | `rag_search_result`, `wiki_index`, `wiki_page` |
| `AgentChatSession` | `agent_chat`, `agent_chat_streaming` |
| `FeedbackStore` | `feedback` |
| `OpenRouterModelCatalogService` | `settings.providers.openrouter`, `byok_status.openrouter` |

## Pagination & windowing

- `episodes_for_selected`: page size 50; older pages fetched on
  scroll-to-bottom action.
- `library`: search-debounced; only the current page emitted.
- `nostr_conversations`: only currently-open conversation's messages
  emitted in full; others summarized.
- `transcript_for_open_episode`: only the visible time window's
  entries + N before/after (smooth scroll buffer).

Action `ScrollToBottom { view, last_seen_id }` requests next page.

## Per-view emit rates

- Default tick: ≈4 Hz (matches Chirp's default; verify at M0).
- `agent_chat_streaming`: ≈30 Hz, gated by NMP-side per-view override.
  If `nmp-core` doesn't yet support per-view rates at M7, file an NMP
  backlog item before M7 starts. Do not implement a Swift-side
  debounce as a substitute (D7 violation).
- `now_playing.position_ms`: position updates from
  `nmp.audio.capability` arrive at ≤4 Hz; kernel collapses into next
  tick.

## Field-by-field optionality (partial)

Every field that can be absent uses Swift `Optional<T>`. Per D1, the
view code renders placeholders gracefully (no force-unwraps; missing
data renders the placeholder).

Sonnet review identified `library_display` as one place where Swift
today derives display fields (accent colors, symbols, % progress)
from raw episode rows in `LibraryDerivedDisplay.swift`. M2 ports
those derivations to Rust and exposes them via this projection so
the view becomes a true thin render. No Swift `switch` on episode
state to pick a color.

## Schema versioning

`schema_version: u32` ships at 1. Bumps on incompatible changes.
Swift's Decodable round-trip must tolerate unknown fields (forward
compat); Rust serialization must include only fields the schema
version declares.

Schema changes during the migration are landed via PR to NMP
plus the matching iOS update in lockstep. There is no "soft" rollout
of a schema bump.
