# M7 — Agent

**Status:** unclaimed
**Scale:** XL
**Depends on:** M3, M6
**Blocks:** M8, M9, M10
**Parallel work units:** 7

---

## Scope

The biggest milestone. Splits across multiple Rust crates (per Codex
review — `podcast-agent` was too large as one):
- `podcast-agent-core` — session, tools, memory, schedule, ask
  coordinator, run log.
- `podcast-llm` — provider router (OpenRouter, Ollama, Perplexity),
  SSE parsing, cost ledger, BYOK.
- Future: `podcast-briefings` (M9), `podcast-voice` (M8),
  `podcast-peer` (M10).

Also requires R2 resolution (per-view emit rate) for streaming tokens.

---

## Pre-flight

- [ ] M3 + M6 exits green.
- [ ] **R2 resolution:** confirm `per-view-emit-rate` NMP BACKLOG
      entry has landed in `nmp-core`. If not, this milestone is
      blocked. Do not proceed with a Swift-side debounce.
- [ ] Confirm agent runaway bounds (R7) accepted: `max_turns`,
      `token_budget`, `cost_budget` configurable.

---

## Parallel work units

### Unit M7.A — `podcast-llm` provider crate

**Tasks:**
- [ ] Port `AgentLLMClient.swift`, `AgentOpenRouterClient.swift`
      (split out of `Features/Agent/`), `AgentOllamaClient.swift`,
      `PerplexityClient.swift`, `OpenRouterModelCatalogService.swift`
      (split out of `Features/Settings/AI/`).
- [ ] Provider routing decision logic.
- [ ] SSE parsing → streaming-token events.
- [ ] BYOK secret retrieval via `nmp.keychain.capability`.
- [ ] Cost ledger.

**Quality gates:**
- [ ] Unit tests for SSE parsing on golden fixtures.
- [ ] Per-provider retry policy (no polling — exponential backoff with
      hard cap) tested with mock clock.

### Unit M7.B — `podcast-agent-core` session + tools

**Tasks:**
- [ ] Agent loop: turn → LLM → tool call → loop.
- [ ] Tool dispatcher + JSON schema export.
- [ ] All AgentTools+* extensions ported as tool modules per
      [`../02-crates.md`](../02-crates.md).
- [ ] Run log, memory store, chat history.
- [ ] Hard caps: max_turns, token_budget, cost_budget per session.
- [ ] Scheduled task runner (next-fire computation; relies on M3
      `nowPlaying` for context).
- [ ] Ask coordinator: sets `pending_ask` on snapshot; UI binds.

**Quality gates:**
- [ ] Every tool tested with a fixture turn + expected projection
      delta.
- [ ] Runaway cap enforced (test simulates infinite tool-call cycle).

### Unit M7.C — `podcast-agent-core` triage + picks + categorization + chapter compiler

**Tasks:**
- [ ] Port `AgentPicksService` (with cache + streaming parser),
      `InboxTriageService` + engagement, `PodcastCategorization/*`,
      `AIChapterCompiler.swift`, `RationaleNarrator.swift`,
      `ThreadingInferenceService.swift`,
      `ImageGenerationService.swift`,
      `YouTubeAudioService.swift`,
      `ChatHistoryStore.swift`.
- [ ] R22: threading inference — port as Rust LLM-tool call. Document
      decision in milestone notes.

**Quality gates:**
- [ ] Unit tests for streaming parsing of picks output.

### Unit M7.D — Streaming-token projection

**Tasks:**
- [ ] `agent_chat_streaming` snapshot field at the per-view emit rate
      enabled by R2.
- [ ] If R2 still not ready, file as `M7-blocked` and pause — do NOT
      add a Swift debounce.

**Quality gates:**
- [ ] Token-by-token streaming visible in UI at >20 Hz.

### Unit M7.E — iOS UI migration: Agent + AgentChat

Files:
- `App/Sources/Features/Agent/*.swift`
- `App/Sources/Features/AgentChat/*.swift`
- Splits required:
  - `AgentChatSession.swift` + `+Conversations.swift` + `+Turns.swift`
    (class excised).
  - `AgentChatTitleGenerator.swift` (class excised).

**Tasks:**
- [ ] Tooling: copy → split → token-swap → fidelity.
- [ ] Bind to `agent_chat`, `agent_chat_streaming`, `agent_run_log`,
      `pending_ask`.
- [ ] AskSheet pops globally from RootShell when `pending_ask` set.

**Quality gates:**
- [ ] Goldens match.

### Unit M7.F — iOS UI migration: Home (Inbox, Picks, Insights)

Files:
- `App/Sources/Features/Home/*.swift`

**Tasks:**
- [ ] Tooling: copy → token-swap.
- [ ] Home tab reads triage + picks + insights projections.

**Quality gates:**
- [ ] Goldens match.

### Unit M7.G — iOS UI migration: Settings AI

Files:
- `App/Sources/Features/Settings/AI/*.swift` (all)
- Splits:
  - `OpenRouterModelCatalogService.swift`
  - `OllamaModelCatalogService.swift`
  - `ElevenLabsKeyValidationService.swift`
  - `ElevenLabsTTSPreviewService.swift`
  - `ElevenLabsVoiceBrowserViewModel.swift`
  - `ElevenLabsVoicesService.swift`
  - `OpenRouterKeyValidationService.swift`

**Tasks:**
- [ ] Tooling.
- [ ] LLMSettingsView (473 LOC) — likely single file; verify under
      500 hard cap. If over, split UI portion into multiple files at
      copy time (per AGENTS.md, this is allowed since it doesn't
      change behavior).

**Quality gates:**
- [ ] Goldens match.

---

## Sequential integration

- [ ] Merge M7.A first (LLM provider — others depend on it).
- [ ] Merge M7.B (agent core).
- [ ] Merge M7.C (specialized agents).
- [ ] Merge M7.D (streaming projection — gated on R2).
- [ ] Merge M7.E + M7.F + M7.G (UI).
- [ ] Live test: full agent turn with tool calls; ask flow pops sheet;
      streaming tokens render smoothly.

---

## Exit checklist

- [ ] AgentChat works end-to-end with all providers.
- [ ] All tools dispatchable from agent: notes, memory, ask, voices,
      TTS, podcast actions, wiki, schedule, owned podcasts, YouTube,
      external (perplexity), conversations, peer actions (M10 stub),
      podcast inventory.
- [ ] Streaming tokens visible.
- [ ] Picks + Inbox triage populate Home.
- [ ] Scheduled tasks fire.
- [ ] Cost ledger visible in Settings.
- [ ] **Swift files deleted:**
  - `App/Sources/Agent/*.swift` (all 40+)
  - `App/Sources/Services/AgentPicksService*.swift`
  - `App/Sources/Services/InboxTriage*.swift`
  - `App/Sources/Services/PodcastCategorization/*.swift`
  - `App/Sources/Services/AIChapterCompiler.swift`
  - `App/Sources/Services/ChatHistoryStore.swift`
  - `App/Sources/Services/RationaleNarrator.swift`
  - `App/Sources/Services/ImageGenerationService.swift`
  - `App/Sources/Services/YouTubeAudioService.swift`
  - `App/Sources/Services/ThreadingInferenceService.swift`
  - `App/Sources/Services/BYOKConnectService.swift`,
    `BYOKCredentialImporter.swift`, `BYOKModels.swift`,
    `AssemblyAICredentialStore.swift`,
    `ElevenLabsCredentialStore.swift`,
    `OllamaCredentialStore.swift`,
    `OpenRouterCredentialStore.swift`,
    `PerplexityCredentialStore.swift`
  - Class parts of: `AgentChatSession`, `AgentLLMClient`,
    `AgentOpenRouterClient`, `AgentOllamaClient`,
    `AgentChatTitleGenerator`,
    `OpenRouterModelCatalogService`, `OllamaModelCatalogService`,
    `OpenRouterKeyValidationService`,
    `ElevenLabsKeyValidationService`,
    `ElevenLabsTTSPreviewService`,
    `ElevenLabsVoiceBrowserViewModel`,
    `ElevenLabsVoicesService`,
    `PerplexityClient`
- [ ] M8 + M9 + M10 unblocked.

## Hand-off

M8/M9/M10 can rely on agent loop + provider router + tool schema.
