# Crates inventory

## A. NMP today (verify before claiming work)

The plan's reference set of NMP crates, as of 2026-05-25. **Verify each
of these against `Cargo.toml` in the NMP repo at the start of the
milestone that uses them** — the Codex review flagged that some of my
original assumptions were wrong (NIP-19 is in `nmp-core/src/nip19.rs`,
not a standalone crate; NIP-44 is provided by `rust-nostr` rather than
a new crate; etc.).

Kernel + framework:
- `nmp-core` — substrate + planner + outbox router + EventStore trait +
  raw C FFI (~71 symbols).
- `nmp-network` — relay connection pool.
- `nmp-router` — routing algorithm (NIP-65, indexers, fallback, blocked,
  override).
- `nmp-routing-core` — shared routing types.
- `nmp-store` — EventStore trait.
- `nmp-nostr-lmdb` — LMDB backend.
- `nmp-app-template` — `register_defaults` for NIP-02/17/57/65 wiring.

Protocol crates (already shipped):
- `nmp-nip01` — events + Profile/Timeline + SendNote.
- `nmp-nip02` — contacts/follows.
- `nmp-nip17` — DMs over gift-wrap.
- `nmp-nip29` — groups.
- `nmp-nip42` (+ `nmp-nip42-types`) — relay AUTH.
- `nmp-nip57` — zaps + LNURL.
- `nmp-nip59` — gift-wrap.
- `nmp-nip77` — negentropy.
- `nmp-threading` — kind-agnostic NIP-10 grouper. (Sonnet review caught
  that I missed this; we use it instead of writing a duplicate.)

Signers:
- `nmp-signers` — local nsec, NIP-46, NIP-07 (web).
- `nmp-signer-iface` — Signer trait.
- `nmp-signer-broker` — NIP-46 broker.

FFI/codegen:
- `nmp-codegen` — per-app FFI codegen.
- `nmp-ffi` — handles.
- `nmp-android-ffi` — JNI bindings.
- `nmp-wasm` — wasm bindgen.

NIP-19 (bech32) lives inside `nmp-core/src/nip19.rs` and is complete
(npub, nsec, note, nprofile, nevent, naddr). No new crate needed.
NIP-44 is consumed via `rust-nostr` integration in `nmp-nip59` and
`nmp-signers`. No new crate needed unless we hit a duplication-risk
boundary.

## B. New NMP crates (Nostr-generic, file BACKLOG entries)

Each below either creates a new NMP crate or formalizes an existing
module. None contain podcast-specific code. Test: would another Nostr
app use this?

### nmp-nip23 — long-form articles (kind:30023)

Skeleton exists in `apps/longform`. Promotion to first-class crate is
deferred unless Podcastr's wiki-long-form publishing actually ships in
v1; default is **skip** for migration scope.

### nmp-nip26 — delegation

Used today by Podcastr (`NostrAgentResponder+Delegation.swift`). NMP
may already have delegation in `nmp-signer-iface` — verify at M1
start. If not, file BACKLOG.

### nmp-nip65 — relay-list query module

May already be covered by `nmp-router`. M1 verifies.

### nmp-nip74 — podcast addressable events (kind:30074, 30075)

Generic to any Nostr podcast client. Podcastr is the proof of demand.
**ADR required before implementation**: pin the schema (kind numbers,
tag layout) so we don't fork if/when a formal NIP appears.

Public API:
- `Nip74Podcast`, `Nip74Episode` event views.
- Actions: `PublishPodcast`, `PublishEpisode`.
- Queries: recent podcasts by author set; episodes by podcast.
- Deps: `nmp-core`, `nmp-router`, `nmp-nip01`.

### nmp-blossom — Blossom media uploads

Generic file-host protocol. Used by Podcastr for clip audio uploads.
Deferred to M10.

### Capability scaffolding

Each capability namespace can live as a module inside `nmp-core::capability::<name>`
(matches Chirp's existing pattern for `keyring` + `http`). Don't proliferate
crates for these. See [`03-capabilities.md`](03-capabilities.md) for
contracts.

Namespaces to add:
- `nmp.audio.capability`
- `nmp.download.capability`
- `nmp.notifications.capability`
- `nmp.stt.capability`
- `nmp.tts.capability`
- `nmp.vector.capability`
- `nmp.spotlight.capability` (iOS-only)
- `nmp.carplay.capability` (iOS-only)
- `nmp.video.capability` (clip export — file BACKLOG; M3 deferral)

## C. New apps/podcast/ Rust crates (podcast-specific)

These live under `apps/podcast/` in the NMP repo, mirroring
`apps/chirp/`. Per the Codex/Sonnet reviews, `podcast-agent` was too
large in the original plan — split here into multiple cohesive crates.

### podcast-core

Domain types + projections + persistence migrations.

Public API:
- Types: `Podcast`, `PodcastId`, `Episode`, `EpisodeId`,
  `PodcastSubscription`, `Chapter`, `Person`, `SoundBite`, `Anchor`,
  `Clip`, `TriageDecision`, `AutoDownloadPolicy`, `EpisodeAuditEvent`,
  `PodcastCategory`, `CategorySettings`, `AdSegment`, `Settings`,
  `Feedback`, `PlayerState`, `Note`, `NostrConversation`,
  `NostrPendingApproval`, `Friend`.
- Actions: `Subscribe`, `Unsubscribe`, `Play`, `Pause`, `Seek`, `Mark*`,
  `CreateClip`, `RecordEngagement`, etc.
- Projections: `LibraryProjection`, `EpisodeProjection`,
  `ClipProjection`, `CategoryProjection`, `TriageProjection`,
  `PlayerProjection`, `LibraryDisplayProjection` (Rust precomputes
  accent colors, symbols, progress %, summaries).
- Persistence migrations: legacy JSON file at App-Group Application
  Support, SQLite episode sidecar, etc. (See `06-cross-cutting.md`.)

Deps: `nmp-core`, `serde`, `chrono`, `uuid`, `sqlite` (for legacy
sidecar read).

### podcast-feeds

RSS/Atom streaming parser, OPML I/O, Podcasting 2.0 chapter fetching,
feed refresh policy.

Public API:
- `parse_rss`, `parse_opml`, `serialize_opml`,
  `parse_podcasting2_chapters`.
- Actions: `RefreshFeed`, `RefreshAllFeeds`, `ImportOpml`, `ExportOpml`.
- Projection: `RefreshStatusProjection`.

Deps: `podcast-core`, `nmp-core`, `quick-xml`, `chrono`.

### podcast-transcripts

Queue + multi-provider STT coordination + parsing + chunking.

Public API:
- `Transcript`, `TranscriptEntry`, `TranscriptStatus`.
- Actions: `IngestTranscript`, `RetryTranscript`, `OverrideProvider`.
- Projections: `TranscriptionQueueProjection`,
  `EpisodeTranscriptProjection`.
- `parse_vtt`, `parse_srt`, `parse_podcasting_json`.
- `chunk_transcript(transcript, policy) -> Vec<Chunk>`.

Deps: `podcast-core`, `nmp-core`.

### podcast-knowledge

RAG orchestration (vector + BM25 hybrid via `nmp.vector.capability`),
wiki generation/verification, embeddings/reranker coordination.

Public API:
- `Chunk`, `ChunkScope`, `ChunkMatch`, `WikiPage`, `WikiSection`,
  `WikiCitation`.
- Actions: `SearchTranscripts`, `SearchWiki`, `GenerateWikiPage`,
  `RefreshWikiPage`, `EmbedChunks`.
- Projections: `WikiIndexProjection`, `WikiPageProjection`,
  `RagSearchResultProjection`.

Deps: `podcast-core`, `podcast-transcripts`, `nmp-core`.

### podcast-agent-core (split from monolithic podcast-agent)

The agent loop, tool dispatcher, scheduled tasks, memory.

Public API:
- `AgentSession`, `AgentTurn`, `AgentMemory`, `AgentScheduledTask`.
- Actions: `StartAgentTurn`, `CancelAgentTurn`, `DispatchTool`,
  `RecordMemory`, `ScheduleTask`, `CancelTask`.
- Projections: `AgentChatProjection`, `AgentRunLogProjection`,
  `ScheduledTaskProjection`.
- Tool schema export (JSON Schema) for LLM providers.

Deps: `podcast-core`, `podcast-knowledge`, `podcast-transcripts`,
`nmp-core`.

### podcast-llm — LLM/provider router (split out)

Provider-agnostic chat completion. Routes to OpenRouter / Ollama /
Anthropic / OpenAI via `nmp.http.capability`. Owns prompt assembly,
SSE parsing, retry policy, token-streaming projection.

Public API:
- `LLMProvider`, `LLMRequest`, `LLMResponse`.
- Actions: `StartCompletion`, `CancelCompletion`.
- Projections: `LLMStreamingTokenProjection`.

Deps: `nmp-core`.

### podcast-briefings — briefing composition (split out)

Briefing scripts, segment lists, stitching policy (segment crossfade
choice). Audio bytes flow through capabilities; this crate owns
sequencing.

Public API:
- `BriefingRequest`, `BriefingScript`, `BriefingSegment`,
  `BriefingState`.
- Actions: `GenerateBriefing`, `PlayBriefing`, `PauseBriefing`.
- Projections: `BriefingPlayerProjection`, `BriefingIndexProjection`.

Deps: `podcast-agent-core`, `podcast-knowledge`, `podcast-core`,
`nmp-core`.

### podcast-voice — voice mode (split out)

Voice turn loop: listen → STT → agent reply → TTS → barge-in handling.
Audio capture + playback via capabilities.

Public API:
- `VoiceSession`, `VoiceTurn`, `VoiceState`.
- Actions: `StartVoice`, `EndVoice`, `Interrupt`, `Push2Talk*`.
- Projections: `VoiceSessionProjection`, `VoiceCaptionProjection`.

Deps: `podcast-agent-core`, `nmp-core`.

### podcast-peer — Nostr peer agents (split out)

NIP-10 thread reconstruction (uses `nmp-threading`), allow-list,
pending approvals, peer-agent inbox.

Public API:
- `Conversation`, `Approval`, `PeerMessage`.
- Actions: `ApprovePeer`, `BlockPeer`, `SendPeerMessage`.
- Projections: `PeerConversationsProjection`, `PendingApprovalsProjection`.

Deps: `podcast-agent-core`, `nmp-threading`, `nmp-nip01`, `nmp-nip17`,
`nmp-core`.

### podcast-discovery

iTunes Search, Podcast Index, NIP-74 publish + discover orchestration.

Public API:
- Actions: `DiscoverPopular`, `DiscoverSearch`, `LookupShow`,
  `PublishOwnedPodcast`, `FetchNostrPodcastFeed`.
- Projections: `DiscoverProjection`, `NostrPodcastFeedProjection`.

Deps: `podcast-core`, `nmp-core`, `nmp-router`, `nmp-nip74`.

### podcast-feedback

`FeedbackStore` extraction — the wss://relay.tenex.chat live WebSocket
becomes a Rust-side NMP relay pool connection. App-specific so it
lives in `apps/podcast/`.

Public API:
- `FeedbackItem`, `FeedbackRelayConfig`.
- Actions: `SubmitFeedback`, `RefreshFeedback`.
- Projections: `FeedbackListProjection`.

Deps: `nmp-nip01`, `nmp-core`.

### nmp-app-podcast

The single Rust artifact iOS/Android/web link. Composes everything.

Crate-type: `staticlib`, `rlib`, `cdylib`.

Composition:
- `nmp-app-template::register_defaults` (NIP-02 follows, NIP-17 DMs,
  NIP-57 zaps, NIP-65 outbox).
- `podcast-core::register`, `podcast-feeds::register`,
  `podcast-transcripts::register`, `podcast-knowledge::register`,
  `podcast-agent-core::register`, `podcast-llm::register`,
  `podcast-briefings::register`, `podcast-voice::register`,
  `podcast-peer::register`, `podcast-discovery::register`,
  `podcast-feedback::register`.
- `nmp-signer-broker::nmp_signer_broker_init`.
- `nmp-nip74::register` (when M10 lands).

FFI symbols:
- `nmp_app_podcast_register(app, viewer_pubkey) -> *mut PodcastHandle`
- `nmp_app_podcast_snapshot(handle) -> *mut c_char`
- `nmp_app_podcast_snapshot_free(ptr)`
- `nmp_app_podcast_unregister(handle)`

File layout: mirror `apps/chirp/nmp-app-chirp/src/ffi/{register, handle, snapshot, actions}.rs`.

## D. Crate sizing & doctrine

Every file in every crate honors 300 LOC soft / 500 LOC hard. If a
module exceeds 300 LOC during implementation, split by cohesive
ownership, not technical role (per NMP AGENTS.md "TEA organization").
