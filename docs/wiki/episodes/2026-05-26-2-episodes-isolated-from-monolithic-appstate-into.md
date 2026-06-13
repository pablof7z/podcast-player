---
type: episode-card
date: 2026-05-26
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
salience: architecture
status: superseded
subjects:
  - observable-granularity
  - episode-state-isolation
  - appstatestore
supersedes: []
related_claims: []
source_lines:
  - 69232-69266
captured_at: 2026-06-12T12:50:20Z
---

# Episode: Episodes isolated from monolithic AppState into separate @Observable property

## Prior State

A single `@Observable var state: AppState` meant any field mutation (episode position, settings change, nostr event) re-rendered every view reading `store.state.*`, because @Observable tracks per stored property, not per field.

## Trigger

Performance investigation confirmed that the single `var state` caused episode writes (position-debounce flush) to invalidate settings/agent/nostr views that don't read episodes.

## Decision

Promoted `episodes` to its own `@Observable` stored property (`store.episodes`). `AppState.episodes` became a serialization-only DTO slot re-composed at the persistence seam via `runStateSideEffects` + `composedState`. Only episode-reading views re-render on episode changes.

## Consequences

- Settings, agent, and nostr views no longer re-render on episode mutations
- Persistence seam requires explicit composition: `snapshot.episodes = episodes` in `runStateSideEffects`
- Init, clearAllData, and kernel-projection whole-struct seams must split then compose
- Merge conflict with concurrent PRs #225 and #226 on same files — required careful rebase catching silent landmine where `priorEpisodesByID` would have read from blank `state.episodes` DTO slot

## Open Tail

- Optional follow-up: split `podcasts`/`subscriptions` out the same way if profiling warrants

## Evidence

- transcript lines 69232-69266

