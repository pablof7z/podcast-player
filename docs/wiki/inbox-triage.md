---
title: Inbox Triage
slug: inbox-triage
topic: agent-system
summary: An autonomous AI Inbox replaces the existing "Featured" surface on Home; after each feed refresh, an agent classifies each new episode as `.inbox` (surfaced on
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12T18:00:00Z
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:d0e6775b-4ac9-4467-b961-7e78de0f61eb
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:6706236b-c94a-4458-aa7b-6f71098aa55b
  - session:2a627da2-be7e-41cb-968e-79e23db03c36
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
  - session:rollout-2026-05-13T16-50-44-019e219a-aaed-75d3-a0e7-1d2221d9b76f
  - session:rollout-2026-05-13T16-51-04-019e219a-f6d8-78d2-8c63-e09938281252
---

# Inbox Triage

## Triage Model

An autonomous AI Inbox replaces the existing "Featured" surface on Home; after each feed refresh, an agent classifies each new episode as `.inbox` (surfaced on Home with a one-line "Because …" rationale chip) or `.archived` (silently soft-hidden: stays in store but drops out of unplayed counts, Continue Listening, recent feed, and Threading topics; still visible on the show page). The AI Inbox operates with full autonomy: there is no user-facing "review mode" for archive decisions. A 10-minute cooldown (`TRIAGE_RETRY_COOLDOWN_SECS`) suppresses proactive triage re-enqueue after a failed pass. The Rust kernel is the source of truth for triage decisions; Swift InboxTriageService was a redundant producer deleted in PR #205.

Inbox triage IS triggered on async subscribe completion (inbox-triage-on-async-subscribe PR): `PodcastAppState.inbox` was flipped from `InboxState` to `Arc<InboxState>` and passed as the 6th arg to `FeedFetchCoordinator::new`; `apply_subscribe_result` calls `self.inbox.maybe_enqueue_triage()` gated identically to the adjacent `auto_categorize`/`auto_refresh_picks` calls. Freshly-subscribed and OPML-imported episodes now triage immediately.

Inbox triage uses the same agent identity and memory as the chat agent, via build_system_prompt_with_memory, rather than a separate LLM pipeline with its own system prompt. The triage agent has access to get_memory_facts, search_library, and set_episode_priorities tools, with a maximum of 6 tool turns per invocation. All needy episodes are sent in a single agent invocation (no chunking), with a user message listing every episode since the last triage check. set_episode_priorities is a single batch-write tool that accepts an array of {episode_id, score, reason, categories} objects, recording all scores in one tool call. After the agent call completes, any episode that still lacks a fresh Ready entry in the triage cache gets stamped as Pending via reconcile_pending, preventing hot-spawn loops.

The LLM scoring cache persists to disk (inbox-triage-cache.json) and reloads on cold launch, with staleness invalidation when feed refresh changes episode metadata.

The triage shimmer in HomeView now reads inboxTriageInProgress from the podcast snapshot projection so the UI shows a loading indicator during background LLM triage.

Destructive/reset actions are not ordinary model-callable tools and require explicit user confirmation outside the agent loop.

Triage decisions are permanent once made; there is no TTL or automatic reconsideration, though user-initiated play on an archived episode recovers it. (Previously: a reconsideration/decay mechanism was proposed but rejected; decisions persist indefinitely.)

PR #383 moved maybe_enqueue_triage out of the snapshot builder and into the dispatch/feed-refresh path, which silently narrowed triage from whenever-snapshot-rebuilds to only-after-successful-feed-refresh, missing cold-start, stale-Pending retry, and fresh-subscribe scenarios. (Previously: triage was triggered on every snapshot rebuild; this was narrowed to feed-refresh only.) This regression was fixed by adding a cold-start/foreground trigger via the auto_download_evaluate op that already runs at first foreground, and by decoupling refresh_all's triage trigger from the any_succeeded gate.

<!-- citations: [^c1691-18] [^rollo-12] [^d0e67-1] [^14943-9] [^67062-4] [^2a627-2] [^55bed-3] [^rollo-143] [^rollo-147] [^c1691-101] [^c1691-115] -->
## Data Model

Episode carries a triageDecision enum (.inbox | .archived) and a triageRationale string, stored as backward-compatible Codable. Triage state (triageDecision, triageRationale, triageIsHero) is preserved across feed refresh upserts so archived episodes do not reappear; the upsert path must explicitly carry forward these fields when merging RSS payloads to prevent archived items from leaking back onto Home before re-triage completes.

<!-- citations: [^d0e67-2] [^rollo-148] -->
## Archive Semantics

Archived episodes are soft-hidden (not deleted) and recoverable from the show page; archive does not pollute play history. Unplayed counts, Continue Listening, recent feed, and Threading Today all skip .archived episodes, while show-page episode lists keep them visible. Archived episodes must be excluded from Threaded Today topic mentions, Spotlight indexing, local search results, agent inventory unplayed counts, and agent prompt context. Episodes destined for archive must be soft-hidden before notifications are sent and before auto-downloads/auto-ingests begin. Playing an archived episode from the show page auto-clears the archive state (via an onClearTriageDecision closure on PlaybackState, wired in RootView to AppStateStore.clearTriageDecision) so it reappears in Continue Listening after pause.

<!-- citations: [^d0e67-3] [^rollo-144] [^rollo-149] -->
## New Shows & Heuristic Fallback

Newly-subscribed shows are identified using subscribedAt < 7 days rather than episode-count heuristics; the prompt tells the agent not to archive them. When no API key is available, the Inbox seeds with a heuristic ('Newest from <show>') instead of leaving Home empty. When LLM triage is unavailable, the inbox falls back to a recency-bucket heuristic with labels "Just published", "Recent", and "This week". On cold start (no memory facts and no chat history), the agent call is skipped entirely and the recency heuristic is used as fallback.

<!-- citations: [^d0e67-5] [^67062-5] [^2a627-3] -->
## Store Invariants

The store and bundle builder enforce that every `.inbox` decision has a non-blank rationale; empty-rationale inbox decisions are dropped at the store boundary and not persisted, so the episode stays untriaged for the next pass. The empty-rationale invariant is enforced at the store boundary: applyTriageDecisions filters out .inbox patches whose rationale is nil or whitespace-only. Notifications, auto-downloads, and other side effects are gated behind triage completion; archived episodes do not trigger notifications or downloads on the same cycle they were created in.

<!-- citations: [^d0e67-6] [^rollo-152] -->
## Hero Selection

The AI Inbox UI replaces "Featured" with the same UX layout: a hero card plus a secondaries rail. The LLM emits an is_hero flag on at most one decision per pass; the parser enforces uniqueness (first wins); the hero is persisted as Episode.triageIsHero and the bundle builder prefers the agent's hero choice over pubDate. The Home Inbox UI composes a hero + 4 secondaries from persisted .inbox episodes, sorted by recency (or agent priority via hero flag). Every inbox item must have a "Because …" rationale chip.

<!-- citations: [^d0e67-7] [^rollo-145] [^rollo-150] -->
## Engagement Display

The engagement signal is surfaced as a subtitle under the Inbox header showing triage recency, pick count, show count, and archived count, scoped by the active category. The section header was renamed from Featured to Inbox (or Inbox · <Category>). The app also shows an 'AI profile' auto-learned from play/skip history visibly on Home, surfaced alongside the Inbox section.

<!-- citations: [^d0e67-8] [^rollo-151] -->
## Code Organization & Debt

The EngagementBuilder logic is extracted into its own file (InboxTriageEngagementBuilder) to keep InboxTriageService under the 300-line soft cap. build_system_prompt_with_memory and AGENT_SYSTEM_PROMPT were moved from agent_handler.rs to agent_llm.rs as pub(crate) items so both chat and triage can share them. run_background_agent_task was added to agent_llm.rs as a wrapper around the shared tool loop, with empty conversation history and triage-specific tool instructions. inbox_llm.rs was gutted to only contain TriageResult and TriageStatus types; all LLM calling code was removed. Episode.swift is at 481 lines (under the 500 hard cap but with limited headroom), flagged for a future PR if it grows. Old AgentPicksService, Prompt, Fallback, and StreamingParser files remain as dead code because three test files still reference them; cleanup is deferred to a follow-up. No tests exist yet for the new triage code.

<!-- citations: [^d0e67-9] [^67062-6] -->
## Android Surfaces

Android Tier-2 Inbox and Transcripts surfaces (PR #398) are implemented as thin-shell Compose rendering on the shared kernel, with InboxAction routing (Triage/Dismiss/MarkListened) and FetchTranscript verified against the Rust podcast.inbox namespace router. <!-- [^c1691-3] -->
