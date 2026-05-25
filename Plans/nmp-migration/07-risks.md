# Risks & open questions

Each risk gets either a mitigation here or a referenced BACKLOG entry.

## R1 — NMP substrate mismatch (Codex finding, BLOCKING resolution)

The Codex review found that `DomainModule`, `ViewModule`,
`IdentityModule` are not implemented in current `nmp-core`. The shipped
substrate is `ActionModule`, `CapabilityModule`, `DomainMigration`,
`KernelEventObserver`.

**Resolution** (in [`01-architecture.md`](01-architecture.md)): the
plan adopts the shipped substrate. Internal Rust types we call
"DomainModule" / "ViewModule" are conventional names, not framework
traits. M0 verifies this against the actual code.

## R2 — Per-view emit rate (Sonnet finding, BLOCKING for M7)

`agent_chat_streaming` projection assumes per-view emit rates above
the default tick. `nmp-core/src/actor/tick.rs` today uses a single
global rate.

**Resolution**: BACKLOG entry `per-view-emit-rate` filed pre-M0. NMP
work lands before M7 starts. If it slips, M7 ships with global-rate
streaming (lower fidelity but functionally correct) plus a follow-up
patch when the infra lands. **No Swift-side debounce as a substitute.**

## R3 — AssemblyAI / ElevenLabs polling (Sonnet finding, BLOCKING for M5)

NMP forbids polling at every layer. AssemblyAI batch and ElevenLabs
Scribe batch endpoints normally complete via webhook or async fetch.

**Resolution**: capability opens a local HTTPS callback endpoint (or
uses push notification fallback). Provider calls back; capability emits
`JobComplete{result}`. M5 ADR specifies the exact transport.

## R4 — FeedbackStore relay client (Sonnet finding)

`FeedbackStore.swift` (369 LOC) maintains an independent live WebSocket
to `wss://relay.tenex.chat`. Completely absent from my original
architecture.

**Resolution**: new `podcast-feedback` Rust crate (see
[`02-crates.md`](02-crates.md) §C). Migration in M10. The feedback
relay URL is a `DomainModule` field, not a Swift constant.

## R5 — `nmp-threading` duplication (Sonnet finding)

`nmp-threading` already provides kind-agnostic NIP-10 grouping. Don't
implement a duplicate in `podcast-peer`.

**Resolution**: `podcast-peer` depends on `nmp-threading`. If
`nmp-threading`'s API doesn't fit, extend it via NMP backlog entry —
do not fork.

## R6 — Keychain access groups (Sonnet finding)

`App/Resources/Podcastr.entitlements` lacks `keychain-access-groups`,
so BYOK secret rebinding may require a transitional release.

**Resolution**: M1 audits the actual `kSecAttrAccessGroup` and decides
between (a) same bundle ID → no transitional release, or (b) re-pairing
flow.

## R7 — Agent runaway (loop bound + cost guard)

The agent turn loop can call an LLM repeatedly. Without bounds, a tool
call that triggers another tool call cycles indefinitely on a metered
plan.

**Resolution**: `podcast-agent-core::session::loop` has hard caps:
- `max_turns_per_session: u32` (default 32; configurable in Settings).
- `token_budget_per_session: u64` (default 200k; configurable).
- `cost_budget_per_day_usd: f32` (default $5.00; configurable).
Breach surfaces as a toast; turn loop halts cleanly.

## R8 — Long episodes (10h+) and partial-file seek

Conference talks and lectures run hours. AVPlayer seek into unbuffered
regions stalls. The `nmp.audio.capability` must report buffer progress
to Rust so the player projection expresses "chapter N seekable,
chapter N+1 pending."

**Resolution**: audio capability emits
`BufferingChange{stalled, likely_to_keep_up}` events; Rust projection
exposes per-chapter buffer state.

## R9 — Sleep timer business logic

`PlaybackState.swift` (497 LOC) owns sleep timer state. Migration moves
this to Rust (`podcast-core::player::sleep_timer`). The capability
becomes a pure `SetSleepTimer{kind, fade_out}` executor.

**Resolution**: Sonnet caught that this was business logic, not "just
copying state." Now explicit in M3 split list.

## R10 — Download resume tokens

`URLSession` background downloads expose resume data on cancel. If lost
between sessions, downloads restart from byte 0.

**Resolution**: `nmp.download.capability` returns resume tokens to Rust
on `Paused`; Rust persists them in `DownloadDomain` records.

## R11 — Vector DB cold-start

Large legacy vector index migration may freeze first launch.

**Resolution**: see `06-cross-cutting.md` §1.2. Default plan adopt-in-place;
fall back to background re-index with progress toast.

## R12 — NIP-74 spec stability

Kinds 30074 / 30075 are not formally standardized.

**Resolution**: `nmp-nip74` ships with an ADR pinning schema. If a
formal NIP appears with different kinds, `nmp-nip74::migrate` re-emits
events under new kinds. No split schema.

## R13 — CarPlay reactivity

CarPlay templates can't observe SwiftUI reactivity natively.

**Resolution**: `Capabilities/CarPlayCapability.swift` subscribes to
`model.$snapshot` via Combine and rebuilds templates on `car_play.rev`
advance.

## R14 — Live Activity update budget

iOS Live Activity has strict frequency caps.

**Resolution**: `live_activity` snapshot field updates only on chapter
changes or every ≥10s. Capability enforces the cap.

## R15 — Multi-provider STT abstraction quirks

AssemblyAI: batch+webhook. ElevenLabs Scribe: batch async OR streaming
WS. Whisper via OpenRouter: sync HTTP. Apple SpeechAnalyzer: on-device.

**Resolution**: each provider's quirks isolated in
`Capabilities/Stt/<provider>Adapter.swift`. Router lives in Rust.
Capability surface unified (see [`03-capabilities.md`](03-capabilities.md)
§5.4).

## R16 — TTS reconnection + barge-in latency

ElevenLabs WS occasionally disconnects mid-utterance. Barge-in must
interrupt within ≤150ms.

**Resolution**: reconnect policy in Rust (`podcast-voice::manager`).
`BargeInDetector` (capability) posts events at ~50 Hz; kernel turns
those into immediate `CancelTtsSession` actions.

## R17 — SwiftUI re-render performance with one big snapshot

Many `@Published` properties → one `snapshot: PodcastUpdate` re-renders
all observers per tick.

**Resolution**: `KernelModel` exposes per-projection accessors with
field-level memoization (computed-property-with-cache pattern from
Chirp). Verify performance at M2 with profile data.

## R18 — Bundle ID continuity

Affects Keychain (R6), App Store update vs. new install, App Group
identifier, push token continuity, deep-link scheme.

**Resolution**: M1 decision. Default: preserve `io.f7z.podcast`.

## R19 — Codex's foundational gap (broad)

Codex says even with the v2 substrate decision (R1), several other
NMP APIs the plan referenced may not exist or differ. Each milestone's
pre-flight includes a "verify against current NMP code" step.

**Resolution**: each milestone page begins with `Pre-flight` boxes
that include "API audit pass" for the touched NMP surface.

## R20 — Effort estimate uncertainty

Codex: 18–30 PM. Sonnet: 10–16 PM. Original: 8–12 PM.

**Resolution**: revise at each milestone exit; this is a sliding
window, not a fixed commitment.

## R21 — Hidden deferrals / "post-M13"

Codex specifically called out that "post-M13" items are hacks under
the zero-hack rule.

**Resolution**: every deferred decision in this plan now either has a
named milestone or is filed as a BACKLOG entry. The plan no longer
contains "post-M13" sinks. Audit at every milestone exit.

## R22 — Threading inference

`ThreadingInferenceService.swift` does NER and clustering in process.

**Resolution**: M7 decides — port as-is to Rust (rust-stanza?), or
convert to LLM tool call. Default plan: LLM tool (simpler, slightly
slower).

## R23 — Agent ask-coordinator UX

When the agent needs user consent ("publish this clip?"), modal must
pop from any tab.

**Resolution**: `pending_ask` snapshot field; root sheet observer pops
existing AskSheet UI when `pending_ask` becomes non-null. Pure
projection-driven; no special wiring.

## R24 — iOS 26 sqlite-vec quirks

`sqlite-vec` is a SQLite extension. iOS 26 may change bundled SQLite
or extension-loading rules under privacy manifest requirements.

**Resolution**: capability checks extension availability at runtime;
graceful degradation = disable vector search, fall back to FTS-only.

## R25 — Multi-bundle UI test capture

Golden screenshots captured from legacy app must use the same SwiftUI
preview environment as the migrated views. Differences in injected
environment values can shift renders without app changes.

**Resolution**: capture goldens with a consistent test host scheme;
both legacy and migrated views use the same fixture-state injection
pattern.

## R26 — Splitting Features files breaks imports

When `AgentChatSession.swift` is split, the View struct still imports
the deleted class until the migration's token-swap fixes the bindings.
This creates a transient broken state.

**Resolution**: split-features.swift is atomic per file — class
excision + token-swap happen in one tool invocation. The intermediate
state is never committed.

## R27 — Stale `WIP.md` entries

Multiple agents working in parallel may leave stale entries if a
worktree is abandoned without PR.

**Resolution**: orchestrator sweeps `WIP.md` on a schedule; entries
older than 48 hours without a corresponding open PR are flagged for
review.

## R28 — Schema-version drift

If Swift's `PodcastUpdate.schema_version` constant lags behind Rust's,
new fields silently fail to decode.

**Resolution**: at every schema change, the Rust serializer asserts
the schema version matches a constant in
`apps/podcast/nmp-app-podcast/src/snapshot.rs`. Swift's
`KernelBridge` reads the version from the snapshot and fails with a
loud error on mismatch.
