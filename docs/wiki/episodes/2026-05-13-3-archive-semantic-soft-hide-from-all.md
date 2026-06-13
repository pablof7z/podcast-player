---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: architecture
status: active
subjects:
  - ai-inbox-triage
  - archive-semantic
  - episode-filtering
supersedes: []
related_claims: []
source_lines:
  - 84-84
  - 924-925
  - 1125-1294
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Archive semantic: soft-hide from all surfaces except show page

## Prior State

No unified concept of 'archived by agent' existed. Episodes were either played or unplayed — no silent suppression state. Archived episodes would leak into Spotlight, in-app search, Continue Listening, unplayed counts, the agent's own context, and threaded-today.

## Trigger

User chose 'soft-hide (recoverable)' for archived episodes (line 84). Codex review subsequently identified 6 specific leak surfaces where archived episodes still appeared (line 924).

## Decision

Archived episodes are filtered from every discovery surface — HomeThreadedTodayView, SpotlightIndexer, PodcastSearchModels, LivePodcastInventoryAdapter, AgentPrompt, Continue Listening, and unplayed counts — but remain visible on the show page as the recovery surface.

## Consequences

- Every new surface that displays unplayed episodes must include a !isTriageArchived filter — this is now a system invariant
- Spotlight (iOS system search) and in-app search are gated consistently, so users can't find archived episodes via either path
- The agent's own prompt context excludes archived episodes, preventing it from recommending episodes it already decided to suppress

## Open Tail

- A future 'Show archived results' toggle in search could relax this per-surface

## Evidence

- transcript lines 84-84
- transcript lines 924-925
- transcript lines 1125-1294

