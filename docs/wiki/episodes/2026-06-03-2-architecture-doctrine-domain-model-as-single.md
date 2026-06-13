---
type: episode-card
date: 2026-06-03
session: 1bfd020d-5183-458d-8f13-fda034490988
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1bfd020d-5183-458d-8f13-fda034490988.jsonl
salience: architecture
status: superseded
subjects:
  - domain-model-source-of-truth
  - view-layer-discipline
supersedes: []
related_claims: []
source_lines:
  - 1068-1076
  - 1362-1373
captured_at: 2026-06-12T13:05:38Z
---

# Episode: Architecture doctrine: domain model as single source of truth, not views probing kernel snapshots

## Prior State

Views contained 7+ inline lookups like (store.kernel?.podcastSnapshot?.downloads?.active ?? []).first(where: { $0.episodeId == episode.id.uuidString })?.progress, directly fingering the Rust FFI snapshot to synthesize a value that should already be on the Episode model. This created a 'persisted vs live' duality where episode.downloadState.progress was stale but views tried to patch it with a live overlay.

## Trigger

Diagnosis of the 0% bug revealed that the scattered inline kernel lookups were architecturally leaky — views were reaching through abstraction layers to compensate for the domain model being out of date

## Decision

One write path (applyDownloadOverlay using fresh downloadSnapshot) keeps the domain model current; views just read episode.downloadState directly. The DownloadProgressBadge.liveProgress parameter and all 'live ?? persisted' patterns are removed from view code.

## Consequences

- No view should ever need to reach into kernel snapshot internals for download progress
- Future download-related UI features use episode.downloadState as the canonical read point
- New kernel.downloadSnapshot property on KernelModel is the single architectural bridge for download state freshness

## Open Tail

*(none)*

## Evidence

- transcript lines 1068-1076
- transcript lines 1362-1373

