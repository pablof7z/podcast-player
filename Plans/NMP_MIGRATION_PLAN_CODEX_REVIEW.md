# NMP Migration Plan Codex Review

Date: 2026-05-25

Scope reviewed:

- Plan: `/home/pablo/Work/podcast/Plans/NMP_MIGRATION_PLAN.md`
- Podcast app: `/home/pablo/Work/podcast/App/Sources/`
- NMP framework: `/home/pablo/Work/nostrmultiplatform/`
- Reference NMP iOS app: `/home/pablo/Work/nostrmultiplatform/ios/Chirp/`
- Reference NMP Rust app: `/home/pablo/Work/nostrmultiplatform/apps/chirp/nmp-app-chirp/`

## Overall Verdict

**SHIP-WITH-REVISIONS.** The migration plan is useful as a strategic outline, but it should not be adopted as the source of truth until the factual mismatches and architecture gaps below are corrected. The plan captures the right end state: Rust-owned business logic, native rendering and OS adapters only, NMP doctrine compliance, and a UI-preservation strategy. However, several core assumptions do not match the current NMP codebase or the podcast app. Most importantly, the plan relies on `DomainModule`, `ViewModule`, and typed module APIs that the current NMP substrate explicitly says do not exist yet, and it treats the podcast app persistence model as a single UserDefaults JSON blob when the current app already uses a file-backed metadata store, a SQLite episode sidecar, transcript/wiki/briefing files, chat history, usage ledger files, Keychain, and scattered UserDefaults.

The plan is salvageable because the high-level sequencing and crate boundaries are close to the right shape. It needs a foundation revision before implementation: a real NMP API inventory, a generated file-by-file disposition table, a persistence inventory, capability ADRs detailed enough for Android and web implementers, and an earlier second-platform proof. Without those revisions, the project will drift into the exact anti-pattern the user forbids: Swift still holding decisions while Rust becomes a partially trusted backend.

## Top 5 Strengths

1. **The plan adopts the right ownership model.** Sections 1.1, 1.2, 2, and 7 correctly state that business logic, state transitions, persistence, networking, ranking, and formatting decisions must move to Rust, while Swift keeps rendering and OS capability adapters. That is aligned with NMP D1, D4, and D7 in `/home/pablo/Work/nostrmultiplatform/docs/product-spec/overview-and-dx.md` §1.5 and `/home/pablo/Work/nostrmultiplatform/docs/product-spec/doctrine.md`.

2. **The UI-preservation goal is explicit.** Section 1.1 says the existing SwiftUI layout should be copied rather than redesigned. That is the right migration posture for an established iOS app with 583 Swift files and about 95K LOC: preserve the product surface, then replace the engine.

3. **The proposed crate taxonomy separates several real domains.** Section 4 distinguishes feeds, transcripts, knowledge, discovery, agent behavior, and app composition. The exact split needs revision, especially around `podcast-agent`, but the plan correctly avoids putting the whole app into one monolithic app crate.

4. **The plan recognizes capability boundaries.** Section 5 has the right instinct: audio, downloads, STT/TTS, notifications, local files, vector storage, CarPlay, Spotlight, and OS integrations are capabilities, not business logic. The designs are not complete enough yet, but the category boundary is directionally correct.

5. **The milestone plan includes deletion sweeps and doctrine checks.** Sections 7, 9, and 12 repeatedly call for no Swift business logic, no direct network/storage access from Swift, and no migration shortcuts. Those checks need to become concrete CI gates, but they are the right constraints.

## Top 10 Issues

### 1. The plan targets NMP module APIs that are not implemented

**Severity: Critical.** Sections 3, 4, 4.7, 8, and Appendix A describe migration work in terms of `DomainModule`, `ViewModule`, `IdentityModule`, view registries, and typed app modules. The current NMP substrate does not provide that runtime. `/home/pablo/Work/nostrmultiplatform/crates/nmp-core/src/substrate/mod.rs:6` says the v2 typed namespace module runtime “does not exist yet.” The same file says `ViewModule` and `IdentityModule` were removed, that there is no shipped `ViewRegistry` or identity-dispatch runtime, and that the current extension mechanism is a raw-event fan-out through `KernelEventObserver` (`mod.rs:21`, `mod.rs:29`). The actual exported substrate traits are `ActionModule`, `CapabilityModule`, `DomainMigration`, and related migration types, not the module graph assumed by the plan.

**Why it matters:** This is a foundation mismatch. If implementation starts against the plan as written, engineers will either invent app-local abstractions that do not compose with NMP or quietly keep logic in Swift while waiting for future NMP APIs. Both outcomes violate D0 and D7.

**Concrete fix:** Add a pre-migration foundation milestone before M0. Either rewrite the podcast architecture around the current shipped substrate (`KernelEventObserver`, `ActionModule`, `CapabilityModule`, `nmp_app_dispatch_action`, and JSON snapshots), or first land the missing NMP v2 typed-module runtime in the framework with tests and reference Chirp usage. The plan should name the exact traits and C symbols it will use, citing `/home/pablo/Work/nostrmultiplatform/crates/nmp-core/src/substrate/capability.rs:11`, `/home/pablo/Work/nostrmultiplatform/crates/nmp-ffi/src/action.rs:99`, and `/home/pablo/Work/nostrmultiplatform/crates/nmp-ffi/src/capability.rs:24`.

### 2. Several proposed NMP crate names are factually wrong or stale

**Severity: Critical.** Section 3 proposes `nmp-nip19`, `nmp-nip23`, `nmp-nip26`, `nmp-nip44`, `nmp-nip65`, `nmp-nip74`, and `nmp-blossom` as NMP crates or planned crates. Current workspace members in `/home/pablo/Work/nostrmultiplatform/Cargo.toml` include `nmp-nip01`, `nmp-nip02`, `nmp-nip17`, `nmp-nip29`, `nmp-nip42`, `nmp-nip42-types`, `nmp-nip57`, and `nmp-nip59`, but not most of those proposed names. NIP-19 is currently implemented inside `/home/pablo/Work/nostrmultiplatform/crates/nmp-core/src/nip19.rs`, not as a crate. NIP-44 is already used through `rust-nostr` features in crates such as `nmp-nip59` and `nmp-signers`; adding a new `nmp-nip44` crate risks duplicating crypto-sensitive code. Relay-list publishing appears to be surfaced through router actions in `/home/pablo/Work/nostrmultiplatform/crates/nmp-app-template/src/lib.rs:124`, not through a standalone `nmp-nip65` crate.

**Why it matters:** Incorrect crate assumptions create duplicate implementations and unstable boundaries. In crypto and signer code, duplication is a security risk, not just a maintenance risk.

**Concrete fix:** Replace Section 3 with an audited NMP capability matrix: current crate, current API, missing functionality, whether podcast needs a new generic NMP module, and whether the work is app-specific. Do not create `nmp-nip44` unless there is a formal ADR explaining why the existing `rust-nostr` integration is insufficient.

### 3. The persistence migration plan is based on a false model of the legacy app

**Severity: Critical.** Section 10.1 says the legacy app stores everything as one JSON blob in App Group UserDefaults under key `"appState"`. The current app does not. `/home/pablo/Work/podcast/App/Sources/State/Persistence.swift:5` says low-cardinality metadata is stored in JSON and high-cardinality episodes are stored in a SQLite sidecar. `Persistence.swift:11` explains that a previous UserDefaults blob was abandoned because `cfprefsd` dropped large blobs. The active state file path is built under App Group Application Support (`Persistence.swift:260`), the legacy key is `"podcastr.state.v1"` (`Persistence.swift:289`), and episodes are written through `/home/pablo/Work/podcast/App/Sources/State/EpisodeSQLiteStore.swift:60`. Additional stores live in `/home/pablo/Work/podcast/App/Sources/Transcript/TranscriptStore.swift`, `/home/pablo/Work/podcast/App/Sources/Knowledge/WikiStorage.swift`, `/home/pablo/Work/podcast/App/Sources/Briefing/BriefingStorage.swift`, `/home/pablo/Work/podcast/App/Sources/Agent/ChatHistoryStore.swift`, and `/home/pablo/Work/podcast/App/Sources/Agent/CostLedger.swift`.

**Why it matters:** A migration plan that misses the actual stores will lose user data or force Swift to keep legacy persistence policy alive. That would violate D4 and D7.

**Concrete fix:** Rewrite Section 10 as a store-by-store migration matrix. For each store, list path, schema, owner, Rust destination, migration idempotence marker, failure behavior, rollback behavior, and native capability required to read the legacy bytes. Swift should provide raw file/SQLite/Keychain/UserDefaults access only; Rust should decide what to migrate, when to retry, and when to mark migration complete.

### 4. The file-by-file migration table is incomplete and contains incorrect facts

**Severity: High.** Section 6 is not complete enough to be used as a migration checklist. The app currently has 583 Swift files under `App/Sources`, grouped roughly as: `Features` 273 files, `Services` 82, `Agent` 52, `Design` 31, `State` 27, `Domain` 24, `Knowledge` 21, `Podcast` 20, `Briefing` 13, `Transcript` 11, `Voice` 9, `CarPlay` 7, `App` 6, `Audio` 5, `AppMain` 1, and `AppIntents` 1. Section 6.13 cites `RootView.swift` as 822 lines, but the current `/home/pablo/Work/podcast/App/Sources/App/RootView.swift` is 416 lines. The plan mentions `AppMain/PodcastApp.swift` and `RootView.swift`, but leaves `AppDelegate.swift`, `AppSidebarView.swift`, `PlayerNavSheets.swift`, `RootView+DeepLink.swift`, and `RootView+Setup.swift` without concrete disposition.

The Services table also misses actual NIP-46 files under `/home/pablo/Work/podcast/App/Sources/Services/Nip46/`, including `BunkerURI.swift`, `ChaCha20.swift`, `Nip44.swift`, `Nip46Message.swift`, `RemoteSignerClient.swift`, and `RemoteSignerTransport.swift`. Section 6.11 lists `Services/PerplexityClient.swift`, but the file is actually `/home/pablo/Work/podcast/App/Sources/Agent/PerplexityClient.swift`.

**Why it matters:** “Copy all SwiftUI files and delete logic later” is not a reliable process when many files in `Features` are sessions, clients, stores, view models, composers, controllers, and workflow objects.

**Concrete fix:** Generate a real inventory from `find App/Sources -type f -name '*.swift'`, and require exactly one disposition for every file: copy as pure UI, split UI from logic, port to Rust, replace with capability adapter, delete, or defer with a blocking ADR. The plan should fail review if any `App/Sources` file lacks a disposition.

### 5. The “UI byte-identical” promise is not realistic with the proposed mechanical rewrite

**Severity: High.** Section 1.1 promises the UI will look exactly like the existing app, and Section 6 says most feature files are copied with environment bindings replaced. That is not enough. Many feature files compute product behavior and display policy locally. Examples include `/home/pablo/Work/podcast/App/Sources/Features/Agent/AgentChatSession.swift`, which owns agent messages, phase, raw LLM messages, history, cancellation, and auto-resume policy; `/home/pablo/Work/podcast/App/Sources/Features/Library/LibraryDerivedDisplay.swift`, which computes accent colors, symbols, progress, summaries, and counts; `/home/pablo/Work/podcast/App/Sources/Features/Feedback/FeedbackStore.swift`, which fetches, signs, filters, sorts, and publishes Nostr feedback; and `/home/pablo/Work/podcast/App/Sources/Features/Settings/DownloadsManagerModels.swift`, which owns status ranks, labels, progress, and action choices.

**Why it matters:** The app can preserve visual layout while still changing visible behavior if display fields, sorting, placeholder states, progress, and summaries move from Swift ad hoc logic to Rust snapshots without golden tests. “Byte-identical” is also not literally measurable in SwiftUI across OS versions, Dynamic Type, device scale, animation timing, and system rendering changes.

**Concrete fix:** Reframe the promise as “visual and interaction parity for supported devices and OS versions, verified by golden screenshots and interaction traces.” Build snapshot fixtures from the current app for Home, Library, Player, Search, Agent, Settings, Wiki, Briefings, Feedback, Onboarding, and error states. Rust should emit display-ready fields where policy is involved. Swift can still lay out labels and colors, but it should not choose sorting, fallback content, summary text, or eligibility.

### 6. Capability bridge designs are not complete enough for Android/web and have D7 risks

**Severity: High.** Section 5 has sketches, not implementable contracts. An Android engineer would still need decisions on threading, lifecycle, permission prompts, cancellation, foreground services, background execution, media sessions, notification channels, network constraints, scoped storage, audio focus, reboot recovery, error taxonomy, correlation lifecycle, and raw-event frequency. Web is weaker still: Section 5.6 puts IndexedDB support “post-M13,” which conflicts with the requirement that a new platform become trivial after migration.

There are D7 risks as well. `VectorCapability.QueryHybrid` can push query policy, BM25/RRF, and reranking into native code unless it is constrained to raw KNN/BM25 primitives. STT/TTS sections mention native adapters for AssemblyAI, OpenAI, Ollama, and ElevenLabs; if those are ordinary HTTP/WebSocket integrations, Rust should orchestrate them through a generic HTTP/WebSocket capability rather than native provider logic. Review prompts, iCloud, Handoff, data export, bundle resources, and WhatsNew are mentioned later but not specified as capabilities in Section 5.

**Why it matters:** Capabilities are where D7 violations usually enter. If native adapters decide retry, provider fallback, queue policy, download eligibility, transcript provider choice, ranking, or prompt eligibility, the migration fails the zero-hack constraint.

**Concrete fix:** Add one ADR per capability before implementation. Each ADR should include Rust request/result schemas, native raw facts, lifecycle idempotence, cancellation, permission states, platform-specific notes for iOS/Android/web, unsupported behavior, error codes, security constraints, and a D7 policy audit. Require an Android stub or small proof for each capability no later than the milestone that introduces it.

### 7. The milestone ordering hides dependency and validation risks

**Severity: High.** Section 9 delays the second-platform proof until M13. That is too late for a migration whose success criterion is trivial Android/web/desktop expansion. It also delays platform integrations to M11 even though `AppDelegate`, deep links, AppIntents, widgets, CarPlay, and root navigation affect boot and routing from the beginning. M7 groups the agent migration before some Nostr peer/discovery work in M10, even though peer agents, feedback, and social workflows depend on signer, NIP-10/NIP-17/NIP-26-style delegation, relay policy, and event provenance. M2 says Swift persistence is deleted at the end, but many later feature migrations still depend on legacy state if the old app continues to run alongside the new shell.

**Why it matters:** Late validation encourages API lock-in around iOS-only assumptions. Dependency mistakes become expensive after 60% of the Swift UI has been rebound to Rust snapshots.

**Concrete fix:** Move a thin Android or web proof to M2 or M3. It does not need the full UI, but it must exercise app initialization, action dispatch, snapshot decode, at least one capability callback, persistence open/migrate/no-op, and a renderable screen. Split M7 into local agent core, LLM/provider capability, peer/social agent, and scheduled/background work. Move boot, deep link, AppIntents/widget/CarPlay routing contracts earlier, even if UI completion remains later.

### 8. `podcast-agent` is too large and crosses too many domain boundaries

**Severity: High.** Section 4.5 makes `podcast-agent` own assistant graphs, tool planning, briefing generation, wiki maintenance, notifications, voice note extraction, peer chat, cost ledger, model catalog, scheduled tasks, and LLM provider routing. That is more than an agent crate; it is a second application core. The current Swift app already shows this pressure: `Agent`, `Briefing`, `Voice`, `Knowledge`, `Features/Agent`, `Features/Briefings`, and settings AI service files contain intertwined state, networking, policy, and UI-facing models.

**Why it matters:** A large `podcast-agent` crate will become the place every hard decision goes. That weakens D0, makes platform proofs harder, and makes it difficult to test pure domain behavior independently from LLM/provider behavior.

**Concrete fix:** Split the agent domain before migration. A better shape is `podcast-agent-core` for conversations, tool plans, budgets, and execution state; `podcast-llm` for provider-agnostic model requests and tool-call protocol; `podcast-briefings` for briefing scripts and queues; `podcast-voice` for voice-note workflow state; `podcast-agent-memory` or a knowledge-facing module for memory/index writes; and `podcast-peer` or `podcast-social` for Nostr peer-agent messages. `nmp-app-podcast` should compose these modules.

### 9. Hidden deferrals conflict with the user’s zero-hack constraint

**Severity: Medium.** The plan contains multiple “investigate later” markers: Section 3.1 says a NIP-19 crate “may exist in part”; Section 3.2 says to “investigate apps/longform”; Section 3.5 says to decide NIP-65 at M1; Section 4.3 says chapter-side parsing stays “for now”; Section 5 defers Android/web sketches to M13; Section 5.6 says web IndexedDB is “post-M13”; Section 11 has “post-M13” and “Decision deferred” items; Appendix A says to decide crate co-location at M0.

**Why it matters:** Some open questions are normal in a draft, but adoption plans need to distinguish unknowns from implementation work. A “zero hacks” plan cannot keep platform contracts, storage backends, module APIs, and crate boundaries as deferred decisions.

**Concrete fix:** Convert every deferral into one of three states: resolved before adoption, tracked as a blocking pre-M0 ADR, or explicitly removed from migration scope with user approval. Do not allow “post-M13” for any requirement needed to claim Android/web/desktop triviality.

### 10. The estimate is optimistic for the verified scope

**Severity: Medium.** Section 14 estimates 8-12 person-months. The app has 583 Swift files and about 95K LOC, with substantial logic in `Features`, `Agent`, `Services`, `State`, `Knowledge`, `Briefing`, `Transcript`, `Voice`, and `Podcast`. The plan also requires multiple new Rust crates, capability bridges, a full persistence migration, Nostr/signer/delegation work, golden UI parity, a second-platform proof, and deletion of legacy logic.

**Why it matters:** An optimistic estimate will push teams to preserve Swift policy as “temporary” glue, especially in feature models and capabilities.

**Concrete fix:** Re-estimate after the inventory and capability ADRs. My current range is **18-30 person-months** for a no-hack, production-quality migration with second-platform validation. A highly focused team with NMP framework changes already landed and a reduced first release could compress calendar time, but 8-12 person-months is credible only if the scope excludes important features or accepts substantial risk.

## D0-D10 Doctrine Compliance Walk-through

**D0, Build apps via extension modules:** At intent level, the plan is aligned. In implementation terms, it currently fails because it names module APIs that the framework does not ship. It also risks pushing podcast-specific request types such as episode/chapter concepts into generic NMP capabilities. Generic NMP should own reusable primitives; podcast-specific meaning should live in app/domain crates.

**D1, Native UI is a pure projection:** The plan states this rule clearly, but the file inventory shows many Swift UI-adjacent files currently hold policy. `AgentChatSession`, `LibraryDerivedDisplay`, feedback stores, settings models, search models, and download models cannot be copied as-is. Rust snapshots need to include display-ready policy outputs where those outputs are meaningful product decisions.

**D2, Negentropy-first sync:** The plan’s Nostr direction is broadly compatible, but it needs a hard rule that no Swift feature store talks to relays or filters/sorts Nostr events. Existing feedback and signer files make this a real risk. Nostr queries should enter through NMP planner/router/substrate paths, not app-local clients.

**D3, User-owned relay topology:** Relay selection, relay-list publishing, NIP-74 schema pinning, and peer-agent routing must be Rust/NMP-owned. The plan should remove any native relay fallback or direct relay URL decision. If a capability needs a network connection, Rust should supply the exact action and provenance context.

**D4, Single writer per fact:** The plan’s goal is right, but Section 10 misses many stores. Until transcripts, wiki pages, briefings, chat history, usage ledger, review prompt markers, profile cache, Keychain signer state, and App Group files are accounted for, D4 is not satisfied.

**D5, Bounded snapshots:** Section 8 proposes a large `PodcastUpdate` snapshot. That is acceptable only if snapshots are bounded by open views and windows. NMP doctrine says event stores never cross FFI. The plan should define open-view registration and per-view projections for Library, Search, Wiki, Agent, Briefings, and Player rather than emitting all app state to Swift.

**D6, Errors are data:** The plan mostly follows this by using JSON results and no Swift exceptions. Capability ADRs must specify error envelopes and ensure native thrown errors are caught and returned as data. Swift UI can render the error, but not classify retry or policy outcomes.

**D7, Capabilities are lifecycle bridges:** This is the highest-risk doctrine. Audio, downloads, STT/TTS, vector storage, notification scheduling, review prompts, iCloud export, and Handoff all need explicit “native reports, Rust decides” contracts. Any native queue policy, fallback provider choice, ranking, retry policy, or prompt eligibility is a D7 violation.

**D8, Multi-platform performance:** The plan mentions 4 Hz normal snapshots and 30 Hz player updates, but it does not prove those rates against current NMP emit mechanics. Chirp’s current iOS bridge uses a large handwritten `KernelBridge.swift`; performance must be verified with real snapshot payload sizes, open-view gating, coalescing, and decode measurements.

**D9, Kernel-owned time:** Existing Swift code uses `Date`, `Calendar`, timers, review-prompt timestamps, chat-history timestamps, and persistence timestamps. The plan needs a rule that Swift may report OS timestamps as raw facts only when Rust requests them or receives an OS event; Rust owns scheduling, freshness, auto-resume windows, prompt cooldowns, and migration timestamps.

**D10, Provenance and private data:** Peer agents, NIP-46/NIP-44/NIP-59, feedback, private notes, Blossom/NIP-74, and transcripts need strict provenance. Because Section 3’s NIP crate plan is stale and Section 10’s store plan is incomplete, D10 needs a dedicated security review before migration starts.

## Missing Pieces in the File-by-File Migration

The largest gap is that Section 6 is not a true disposition table. It should cover every Swift file under `App/Sources`, not just representative families.

Concrete missing or under-specified areas:

- `/home/pablo/Work/podcast/App/Sources/App/AppDelegate.swift`, `AppSidebarView.swift`, `PlayerNavSheets.swift`, `RootView+DeepLink.swift`, and `RootView+Setup.swift` need explicit routing, lifecycle, and platform-integration dispositions.
- `/home/pablo/Work/podcast/App/Sources/Services/Nip46/` needs a complete Rust/signer migration plan, including `BunkerURI.swift`, `ChaCha20.swift`, `Nip44.swift`, `Nip46Message.swift`, `RemoteSignerClient.swift`, and `RemoteSignerTransport.swift`.
- `/home/pablo/Work/podcast/App/Sources/Features/Feedback/` is a Nostr client and workflow surface, not pure UI. It needs a Rust home.
- `/home/pablo/Work/podcast/App/Sources/Features/Agent/`, `Features/Settings/AI/`, `Features/Briefings/`, `Features/Voice/`, and `Features/Wiki/` contain sessions, model catalogs, clients, controllers, composers, and view models that must be split.
- `/home/pablo/Work/podcast/App/Sources/Design/` is not automatically safe to copy. `DateExtensions.swift`, markdown rendering helpers, image caching/configuration, text highlighting, and formatting helpers must be audited for policy.
- Transcript, wiki, briefing, chat history, usage ledger, and review-prompt storage are missing from the persistence migration.
- AppIntents, widgets, CarPlay, Spotlight, Handoff, bundle resources, WhatsNew display state, and iCloud/export behavior need capability or projection contracts, not just late “platform integration” work.

## Per-Milestone Risk Assessment

| Milestone | Risk | Required revision |
| --- | --- | --- |
| M0, skeleton | High | Add an NMP foundation gate. The current plan cannot rely on `DomainModule` or `ViewModule`; choose current C-ABI/JSON substrate or land the missing runtime first. |
| M1, identity/Nostr basis | Medium | Correct crate assumptions around NIP-19, NIP-44, NIP-65, signer, NIP-46, and router integration. Avoid duplicate crypto. |
| M2, feeds/library/persistence | High | Rewrite persistence migration from actual file/SQLite/sidecar stores. Do not delete Swift persistence until all dependent features are ported or isolated. |
| M3, audio/player | Medium | Define Android audio focus, MediaSession, background playback, remote commands, route changes, and artwork handling now. |
| M4, downloads | Medium | Add WorkManager/foreground-service/scoped-storage equivalents and clarify that Rust owns download policy, retries, and eligibility. |
| M5, transcripts/search | Medium | Decide provider orchestration. Native should not own HTTP provider policy unless a native SDK is unavoidable. |
| M6, knowledge/wiki/vector | High | Replace `QueryHybrid` with raw primitives or a Rust-owned vector store. Web cannot be post-M13 if multiplatform triviality is a goal. |
| M7, agent | High | Split the crate and milestone. Separate local agent core, LLM/provider capability, peer/social agent, scheduled work, and memory writes. |
| M8, voice notes | Medium | Clarify capture lifecycle, on-device vs network STT/TTS, permission states, and background behavior. |
| M9, player polish/CarPlay | Medium | CarPlay and Now Playing are rendering surfaces, but browse-tree and queue policy must come from Rust snapshots. |
| M10, Nostr publishing/NIP-74 | High | Too late for social/feedback/peer-agent dependencies. Move needed Nostr primitives earlier or split features that depend on them. |
| M11, platform integrations | High | Deep links, AppIntents, widgets, boot routing, review prompt, iCloud/export, and Handoff need earlier contracts. |
| M12, parity deletion | Medium | Deletion should be driven by generated inventory and CI gates, not manual sweeps. |
| M13, second platform | High | Too late. Add a second-platform proof in M2/M3 and require each capability ADR to include Android/web acceptance. |

## Effort Estimate Critique

The 8-12 person-month estimate is optimistic for the actual scope. This is not just a mechanical SwiftUI rebinding. The migration includes a new Rust domain model, event ingestion, persistence migration, signer/Nostr/delegation work, agent execution, LLM provider plumbing, transcripts, knowledge/vector search, downloads, media playback, CarPlay/Now Playing, notifications, widgets/AppIntents/deep links, and a second platform proof. The current Swift app has enough business logic embedded in feature-layer files that every major screen will require careful extraction, not a simple environment-object replacement.

A credible no-hack estimate is **18-30 person-months**. The lower end assumes the NMP foundation work is resolved quickly, the team accepts current C-ABI/JSON snapshot patterns, and the first parity target excludes some long-tail integrations. The higher end assumes full feature parity, Android/web validation, complete migration of all stores, robust golden UI testing, and production-grade capability implementations. Calendar time can be shorter with parallel work, but only if crate boundaries, capability ADRs, and file dispositions are locked early.

## Recommended Changes Before Adopting

1. Add a pre-M0 NMP API audit that replaces every assumed API with the exact current trait, function, crate, or ADR needed to create it.
2. Generate and commit a complete `App/Sources` file disposition table. No file should be covered by a wildcard without proof that it is pure UI.
3. Rewrite Section 10 around the actual persistence stores: App Group metadata JSON, SQLite episode sidecar, transcript files, wiki files, briefing files/media, chat history, usage ledger, Keychain, UserDefaults markers, and caches.
4. Split `podcast-agent` before implementation. Keep LLM/provider, briefing, voice, peer/social, memory, and core agent state separate.
5. Create capability ADRs for audio, downloads, notifications, HTTP/WebSocket, STT, TTS, vector/search storage, file import/export, Keychain/signer, review prompt, iCloud, AppIntents/widgets, CarPlay, Spotlight, Handoff, and bundle resources.
6. Move second-platform validation to M2/M3. M13 should be hardening, not the first time the architecture meets Android or web.
7. Replace “UI byte-identical” with a measurable parity contract: golden screenshots, interaction traces, accessibility checks, and fixture-driven snapshot comparisons.
8. Convert every “TBD,” “investigate later,” “post-M13,” and “decision deferred” item into a blocking ADR or remove it from scope with explicit user approval.
9. Add CI gates that scan Swift for forbidden direct networking, persistence, sorting/filtering policy, date/time policy, provider routing, relay decisions, and business state mutation, with allowlists for rendering-only code.
10. Re-estimate after the above revisions. Until then, treat 8-12 person-months as an optimistic draft number, not a planning commitment.

The migration should proceed, but only after these revisions. The plan has the right ambition; it needs to become a verified engineering contract rather than a mostly correct narrative.
