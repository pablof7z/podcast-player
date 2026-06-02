---
title: NMP v0.1.0 Adoption
slug: nmp-v0-1-0-adoption
summary: The NMP v0.1.0 adoption was scoped to one mandatory item (store_open_failure alert) plus a ride-along fix, executed in a single worktree.
tags:
  - nmp
  - v0.1.0
  - adoption
  - plan
  - migration
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# NMP v0.1.0 Adoption

> The NMP v0.1.0 adoption was scoped to one mandatory item (store_open_failure alert) plus a ride-along fix, executed in a single worktree.

## Scope

The NMP v0.1.0 adoption (75 commits, ~38k insertions ahead of the previous pin `2f06cc66`) was decomposed into four items:

1. **`store_open_failure` (mandatory)** — The host MUST surface LMDB-open-failure diagnostics to the user. Implemented as a SwiftUI alert on `RootView`.
2. **`active_account_handle()` (optional, deferred)** — Direct slot read for the signed-in pubkey, replacing snapshot polling. Deferred because the pubkey already arrives reactively each tick.
3. **Typed FlatBuffers sidecar (speculative, deferred)** — ADR-0037 per-key optimization. Not an app-facing choice; blocked on a feed migration that doesn't exist.
4. **TUI unused-import warning (trivial)** — One-line `cargo fix` ride-along. <!-- [^14943-62] -->

## Execution Decision

The planner recommended (and the user approved) a single-worktree approach rather than fanning out multiple agents. The coordination overhead of a multi-agent fan-out would exceed the work itself. All adoption work landed in worktree `podcast-player-nmp-adopt` on branch `feat/nmp-store-open-failure-alert`. <!-- [^14943-63] -->

## Work Tracking

The WIP tracker (`WIP.md` in the main repo, gitignored) records active work items with branch, PR, and status. Each entry includes `added`, `branch`, and `pr` (optional) fields. When work is merged, entries move from Active to Recent History. The tracker is never committed. <!-- [^14943-64] -->

## Deferred Items

Non-blocking follow-ups documented in the PR: a few non-subscribe-path mirror structs (WikiArticle, BriefingSnapshot, KnowledgeSearchResult, CategoryBrowseItem, SocialSnapshot) may need the same default-tolerant wrappers when those features carry data; a relaunch-persistence quirk (separate data layer, not addressed).

<!-- citations: [^14943-65] [^14943-13] -->
## See Also
- [[store-open-failure-alert|Store Open Failure Alert]] — related guide
- [[codex-review-gate|Codex Review Gate]] — related guide
- [[known-bug-patterns|Known Bug Patterns]] — related guide

