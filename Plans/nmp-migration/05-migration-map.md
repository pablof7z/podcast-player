# File-by-file migration map

For every file under `/home/pablo/Work/podcast/App/Sources/`, one
disposition:

- **C** — Copy verbatim via `ci/migration/copy-features.sh` (UI files
  in `Features/` and `Design/` only).
- **S** — Split-then-copy: `cp` then `Edit` to excise a business-logic
  class declaration. View struct bytes preserved.
- **A** — Adapt to a pure capability executor under
  `ios/Podcast/Podcast/Capabilities/`. No business decisions remain.
- **D** — Delete & replace with Rust (named destination crate).

Each disposition row names the destination Rust crate (or the new
Swift Capability file).

## A. Token-swap conversions (apply to every C/S file)

Run via `ci/migration/apply-token-swap.swift` (SwiftSyntax-based, AST
edits, not regex):

| Legacy Swift | Migrated Swift |
|---|---|
| `@EnvironmentObject var store: AppStateStore` | `@EnvironmentObject var model: KernelModel` |
| `store.appState.<field>` | `model.snapshot?.<field> ?? <default>` |
| `AudioEngine.shared.play(episode)` | `model.playEpisode(episode.id)` |
| `AgentSession.shared.send(turn)` | `model.sendAgentTurn(text)` |
| `RAGService.shared.search(query)` | `model.searchTranscripts(query)` |
| `NostrRelayService.shared.publish(event)` | (forbidden — agents that hit this rewrite must error) |
| `Persistence.save()` | (forbidden — kernel persists) |
| `Service.shared.X()` | `model.X()` (per service-call table in each milestone) |

## B. Domain (`App/Sources/Domain/`) — all D

24 files. Targets:

| File | → |
|---|---|
| AppState.swift | `podcast-core` + snapshot |
| AgentActivity.swift | `podcast-agent-core::types` |
| AgentMemory.swift | `podcast-agent-core::memory::types` |
| AgentScheduledTask.swift | `podcast-agent-core::schedule::task` |
| Anchor.swift | `podcast-core::types::anchor` |
| ChapterAgentContext.swift | `podcast-agent-core::tools::types` |
| Clip.swift | `podcast-core::types::clip` |
| EpisodeComment.swift | `podcast-core::types::comment` |
| Friend.swift | `nmp-nip02` + `podcast-peer` |
| ItemColorTag.swift | `podcast-core::types` |
| LLMProvider.swift | `podcast-llm::provider` |
| NostrConversation.swift | `podcast-peer::conversation` |
| NostrPendingApproval.swift | `podcast-peer::approval` |
| Note.swift | `podcast-core::types::note` |
| NoteAuthor.swift | `podcast-core::types::note` |
| PendingFriendMessage.swift | `podcast-peer::pending` |
| RelativeDateBucket.swift | `podcast-core::types::time` |
| RelativeTimestamp.swift | `podcast-core::types::time` |
| Settings.swift | `podcast-core::settings` |
| Settings+Embeddings.swift | `podcast-knowledge::settings` |
| ThreadingMention.swift | `podcast-agent-core::threading` |
| ThreadingTopic.swift | `podcast-agent-core::threading` |
| TranscriptAgentContext.swift | `podcast-agent-core::tools::types` |
| VoiceNoteAgentContext.swift | `podcast-agent-core::tools::types` |

## C. State (`App/Sources/State/`) — all D

27 files. AppStateStore + extensions + persistence + episode SQLite +
cost ledger — all replaced by Rust kernel state + LMDB + per-store
migration shims (see [`06-cross-cutting.md`](06-cross-cutting.md)).

Special:
- `EpisodeSQLiteStore.swift` → read at migration time only; bytes
  flowed into Rust via `podcast-core::migration::from_episode_sqlite`.
  After M2, deleted.
- `AppStateStore+AdSegments.swift` → `podcast-core::episode::ad_segment`
  (Sonnet review caught this was missing in the original plan).
- `CostLedger.swift` → `podcast-llm::cost`.

## D. Podcast (`App/Sources/Podcast/`) — all D

20 files. Targets: `podcast-core::*` and `podcast-feeds::*` (see file
table in original draft — preserved verbatim, each file mapped).
Migration happens in M2.

## E. Audio (`App/Sources/Audio/`) — all A

5 files → `ios/Podcast/Podcast/Capabilities/Audio*.swift`. AudioEngine
becomes pure AVPlayer driver; AudioSessionCoordinator becomes the
session sub-component; NowPlayingCenter becomes a metadata sub-component;
SleepTimer logic moves to Rust (`podcast-core::player::sleep_timer`).

Migration in M3.

## F. Transcripts (`App/Sources/Transcript/`) — A + D

| File | Disposition | Destination |
|---|---|---|
| AppleNativeSTTClient.swift | A | `Capabilities/Stt/AppleNativeAdapter.swift` |
| AppleSTT+TranscriptAdapter.swift | D | merge into adapter or `podcast-transcripts::providers::apple_native` |
| AssemblyAITranscriptClient.swift | A | `Capabilities/Stt/AssemblyAIAdapter.swift` (HTTP envelope only; no polling) |
| ElevenLabsScribeClient.swift | A | `Capabilities/Stt/ElevenLabsAdapter.swift` |
| OpenRouterWhisperClient.swift | A | `Capabilities/Stt/WhisperAdapter.swift` |
| Transcript.swift | D | `podcast-transcripts::types` |
| TranscriptionQueue.swift | D | `podcast-transcripts::queue::queue` |
| Parsing/* | D | `podcast-transcripts::parse::*` |

Migration in M5.

## G. Knowledge (`App/Sources/Knowledge/`) — A + D

21 files. All D except `VectorIndex.swift` which becomes A
(`Capabilities/VectorCapability.swift`). RAG/wiki orchestration to
`podcast-knowledge`. M6.

## H. Agent (`App/Sources/Agent/`) — all D

40+ files. The biggest cluster. Split across Rust crates:
- agent loop, tool dispatch, schemas, memory, schedule, ask coordinator,
  RunLog, Skills → `podcast-agent-core`
- LLM provider clients (`AgentLLMClient`, `AgentOpenRouterClient`,
  `AgentOllamaClient`, `PerplexityClient`) → `podcast-llm`
- briefing-adjacent (`AgentTTSComposer`, `BriefingComposer adapter`)
  → `podcast-briefings`
- peer (`AgentRelayBridge`, `NostrPeerAgentPrompt`,
  `NostrAgentResponder+Delegation`) → `podcast-peer`
- voice (`VoiceItemService` referenced from `AgentTools+TTS`)
  → `podcast-voice`

Migration spread across M7 (core agent), M8 (voice), M9 (briefings),
M10 (peer).

## I. Voice (`App/Sources/Voice/`) — A + D

9 files. STT/TTS clients → A (Capabilities). Audio session bridge → A
merged with audio capability. Turn loop, types, caption, delegate → D
to `podcast-voice`. M8.

## J. Briefing (`App/Sources/Briefing/`) — all D

13 files → `podcast-briefings::*`. M9.

## K. Nostr services — all D

| File | → |
|---|---|
| NIP19.swift | already in `nmp-core::nip19` (skip, no new crate) |
| Bech32.swift | already in `nmp-core::nip19` |
| NIP65RelayFetcher.swift | `nmp-router` query (verify; possibly new `nmp-nip65` BACKLOG) |
| NostrRelayService.swift | `nmp-core` + `nmp-network` |
| UserIdentityStore.swift (+ extensions) | `nmp-signers` + `nmp-cap-keychain` |
| Nip46/* (all 9 files — Sonnet review caught the 6 I missed) | `nmp-signers::nip46` (BunkerURI, Nip46Message, RemoteSignerClient, RemoteSignerTransport) + `nmp-signers::crypto` (Nip44, ChaCha20 — verify against rust-nostr) |
| NostrAgentResponder.swift | `podcast-peer::relay_bridge` |
| NostrAgentResponder+Delegation.swift | `podcast-peer::delegation` (+ `nmp-nip26` BACKLOG entry if needed) |
| NostrCommentService.swift | `nmp-nip01` (kind:1 publish on episode) |
| NostrCredentialStore.swift | `nmp-signers` + Keychain capability |
| NostrEventPublisher.swift | `nmp-nip01` SendNote |
| NostrKeyPair.swift | `nmp-signers::types` |
| NostrPeerAgentPrompt.swift | `podcast-peer::prompt` |
| NostrPodcastDiscoveryService.swift | `podcast-discovery::nostr::discover` (uses `nmp-nip74`) |
| NostrPodcastPublisher.swift | `podcast-discovery::nostr::publish` (uses `nmp-nip74`) |
| NostrProfileFetcher.swift | `nmp-nip01` Profile view |
| NostrThreadFetcher.swift | `nmp-nip01` Thread view + `nmp-threading` |

Migration: M1 (identity, kind:0/kind:65, signer), M10 (peer agents,
NIP-74, peer relay).

## L. Other Services (`App/Sources/Services/`) — mixed

Per file:

| File | Disp | → |
|---|---|---|
| AIChapterCompiler.swift | D | `podcast-agent-core::chapter_compiler` |
| AgentPicks* (3 files) | D | `podcast-agent-core::picks` |
| AssemblyAICredentialStore.swift | D | BYOK via keychain capability |
| BYOKConnectService.swift (+Importer, Models) | D | `podcast-llm::byok` |
| BlossomUploader.swift | D | `nmp-blossom` (new NMP crate, M10) |
| ChaptersHydrationService.swift | D | `podcast-feeds::chapters::hydrate` |
| ChatHistoryStore.swift | D | `podcast-agent-core::session::history` |
| ClipBoundaryResolver.swift | D | `podcast-core::clip::resolver` |
| ClipExporter.swift | D | `podcast-core::clip::export` |
| DataExport.swift | A | `Capabilities/DataExportCapability.swift` |
| DeepLinkHandler.swift | D | `podcast-core::deeplink` |
| ElevenLabsCredentialStore.swift | D | BYOK keychain |
| EpisodeAuditLogStore.swift | D | `podcast-core::audit::store` |
| EpisodeDownloadService(+ext) | A | `Capabilities/DownloadCapability.swift` + policy in `podcast-feeds` |
| EpisodeMetadataIndexer.swift | D | `podcast-knowledge::index` |
| HandoffActivityType.swift | D | `podcast-core::handoff` + handoff capability |
| ITunesSearchClient.swift | D | `podcast-discovery::itunes::client` |
| ImageGenerationService.swift | D | `podcast-agent-core::tools::image_gen` |
| InboxTriage* (3 files) | D | `podcast-agent-core::triage` |
| KeychainStore.swift | A (copy from Chirp) | `Capabilities/KeychainCapability.swift` |
| NotificationService.swift | A | `Capabilities/NotificationsCapability.swift` |
| NowPlayingSnapshotStore.swift | D | kernel `now_playing` projection |
| OllamaCredentialStore.swift / OpenRouterCredentialStore.swift / PerplexityCredentialStore.swift | D | BYOK keychain |
| (PerplexityClient.swift — in Agent/, not Services/) | D | `podcast-llm::providers::perplexity` |
| PodcastCategorization/* | D | `podcast-agent-core::categorization` |
| RAGService.swift (+Adapters) | D | `podcast-knowledge::rag` |
| RationaleNarrator.swift | D | `podcast-agent-core::picks::rationale` |
| ReviewPrompt.swift | A | `Capabilities/ReviewPromptCapability.swift` (decision in `podcast-core::review_prompt`) |
| SpotlightIndexer.swift | A | `Capabilities/SpotlightCapability.swift` |
| SubscriptionRefreshService.swift / SubscriptionService.swift | D | `podcast-feeds::refresh` |
| ThreadingInferenceService.swift | D | `podcast-agent-core::threading::service` |
| TranscriptIngestService(+ext) | D | `podcast-transcripts::queue` |
| TranscriptStore.swift | D | `podcast-transcripts::queue::store` |
| VoiceItemService.swift | D | `podcast-voice::items` |
| WhatsNew.swift | D | `podcast-core::whatsnew` + `Capabilities/WhatsNewBundleCapability.swift` |
| WikiRefreshExecutor.swift | D | `podcast-knowledge::wiki::triggers` |
| YouTubeAudioService.swift | D | `podcast-agent-core::youtube` |
| iCloudSettingsSync.swift | A | `Capabilities/iCloudSyncCapability.swift` |

## M. Features (`App/Sources/Features/`) — see §6.12 in milestones

273 files. Mostly C (literal copy); 22 files on the split list (S).
See each milestone for the per-file split target + Rust destination.
Token-swap pass applies to every copied file.

## N. App / RootView (`App/Sources/App/`, `AppMain.swift`) — C with split

| File | Disp |
|---|---|
| AppMain.swift | C → `ios/Podcast/Podcast/App/PodcastApp.swift` (renamed; mirror `ChirpApp.swift`) |
| RootView.swift (416 LOC; Sonnet caught my mis-count of 822) | C (single file is under the limit) |
| AppDelegate.swift | C (lifecycle hooks only) |
| AppSidebarView.swift | C |
| PlayerNavSheets.swift | C |
| RootView+DeepLink.swift | C (dispatches actions to Rust deeplink module) |
| RootView+Setup.swift | C (kernel startup wiring) |

## O. Platform integrations

| Area | Disp |
|---|---|
| AppIntents/StartVoiceModeIntent.swift | A — dispatches Rust action on invocation |
| CarPlay/* (7 files) | A — render templates from `model.snapshot?.car_play`; Combine bridge |
| Widget/* | A — read App Group JSON file written by Rust |

## P. Resources

- `App/Resources/whats-new.json` — copy verbatim; policy of "show new"
  moves to Rust.
- `App/Resources/Assets.xcassets` — copy verbatim.
- `App/Resources/Podcastr.entitlements` — copy with appropriate
  rename + audit `keychain-access-groups` (Sonnet caught that the
  group is missing today and may block BYOK migration).

## Q. Design utilities

- `App/Sources/Design/*.swift` (Haptics, GlassSurface, PressableStyle,
  ShakeDetector, AppTheme) — C (pure UI utilities).
- `App/Sources/Design/DateExtensions.swift` — audit before C; if it
  contains relative-time policy, port to Rust.

## R. Inventory enforcement

Before any milestone with `Features/` work, agent runs:

```sh
find App/Sources/Features -type f -name "*.swift" \
  | xargs grep -l -E 'class .*(ObservableObject|Service|Store|Session|Client|Controller|Composer|ViewModel)\b|@Observable class' \
  | sort > /tmp/features-with-logic.txt
```

Every file in the output must appear in some milestone's split table
or this map's §M tables before the milestone proceeds.

Periodically refresh the legacy inventory (new files may be added to
the legacy tree between milestones — though that should be rare).
