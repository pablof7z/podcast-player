---
type: episode-card
date: 2026-06-03
session: 1bfd020d-5183-458d-8f13-fda034490988
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1bfd020d-5183-458d-8f13-fda034490988.jsonl
salience: root-cause
status: active
subjects:
  - download-progress-stuck
  - podcast-snapshot-hash-gate
supersedes:
  - 2026-06-02-2-download-progress-invisible-in-ui-downloadqueuesnapshot
related_claims: []
source_lines:
  - 1-2
  - 921-923
  - 1362-1373
  - 1905-1918
captured_at: 2026-06-12T13:05:38Z
---

# Episode: Download progress stuck at 0% — podcastSnapshot hash-gate excluded live progress

## Prior State

All views (EpisodeRow, EpisodeDetailView, EpisodeDetailHeroView, MiniPlayerView, PlayerView, DownloadsManagerView) read live download progress from kernel.podcastSnapshot.downloads.active. But podcastSnapshot is hash-gated and explicitly excludes d.progress from its content hash to prevent list-view re-renders at download frequency. This meant progress was always stale — showing 0% until the download completed.

## Trigger

User reported download button stuck at 0% forever. Code investigation (line 921) confirmed: 'KernelModel.podcastSnapshot is hash-gated and explicitly excludes d.progress from the hash — so podcastSnapshot never updates during a download.'

## Decision

Introduced a dedicated kernel.downloadSnapshot property (updated on every accepted frame where downloads actually changed via Equatable diff), wired it into AppStateStore's applyDownloadOverlay and the withObservationTracking loop, so episode.downloadState.progress is always current. Views now read episode.downloadState directly — no inline kernel-snapshot fishing.

## Consequences

- Download progress now advances live (verified at 3% on simulator, advancing correctly)
- Views are dumb readers of the domain model; no more 'live ?? persisted' duality scattered across 6+ call sites
- podcastSnapshot remains hash-gated for list-view performance (no 4Hz re-renders); downloadSnapshot carries the hot path
- Formatter reverts some view-level simplifications, but they remain correct because both values are now identical

## Open Tail

- Formatter may keep reverting view-file simplifications; the architectural fix in KernelModel/AppStateStore is what matters
- The DownloadProgressBadge.liveProgress parameter could be fully removed in a follow-up cleanup

## Evidence

- transcript lines 1-2
- transcript lines 921-923
- transcript lines 1362-1373
- transcript lines 1905-1918

