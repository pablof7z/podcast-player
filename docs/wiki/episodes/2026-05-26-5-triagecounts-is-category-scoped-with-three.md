---
type: episode-card
date: 2026-05-26
session: 14943b9b-5bf3-4317-bc44-298a773bc75e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/14943b9b-5bf3-4317-bc44-298a773bc75e.jsonl
salience: product
status: active
subjects:
  - triage-counts-design
  - homeview-performance
supersedes: []
related_claims: []
source_lines:
  - 69031-69060
captured_at: 2026-06-12T12:50:20Z
---

# Episode: TriageCounts is category-scoped with three values, not a single Int

## Prior State

Task pseudocode specified a single `pendingTriageCount: Int` plus `heroEpisodeIds`, implying one count value for HomeView.

## Trigger

Code investigation revealed `triageCounts` is category-scoped via `allowedSubscriptionIDs` and returns three values (inbox, archived, shows). A single Int would drop two of the three counts and could not serve the scoped case. `heroEpisodeIds` was a red herring — `triageCounts` never reads hero status.

## Decision

Implemented three per-show stored buckets (`triageInboxCountByShow`, `triageArchivedCountByShow`, `triageDecidedShows`) in `AppStateStore`, populated in the single existing `recomputeEpisodeProjections()` loop, with a `triageRollup(allowed:)` read helper. HomeView reads from cache at O(1) for All and O(category size) when scoped.

## Consequences

- HomeView body reads are O(1) for All case vs O(N-episodes) per render
- Edge case preserved: `triageDecidedShows` is load-bearing because a played-`.inbox`-only show counts toward 'shows' yet adds zero to both count dicts
- AppStateStore.swift exceeded 500-line hard limit (602 lines), deferred split to BACKLOG

## Open Tail

- Deferred `appstatestore-split` to BACKLOG due to 500-line limit

## Evidence

- transcript lines 69031-69060

