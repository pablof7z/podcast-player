---
type: episode-card
date: 2026-06-02
session: e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/e1cfd663-230d-4f78-9078-0c9ed8b6a4bb.jsonl
salience: product
status: superseded
subjects:
  - download-progress
  - download-state-projection
  - ui-feedback
supersedes: []
related_claims: []
source_lines:
  - 1865-1895
  - 1914-1935
  - 2013-2037
  - 2060-2089
captured_at: 2026-06-12T12:55:10Z
---

# Episode: Download progress invisible in UI — DownloadQueueSnapshot never overlaid onto episodes

## Prior State

`EpisodeSummary.toEpisode()` only mapped episodes to `.downloaded` (if `downloadPath` exists) or `.notDownloaded` — the `.queued`, `.downloading(progress:)`, and `.failed` cases were never produced. The `DownloadQueueSnapshot.active` data from Rust was completely ignored in the projection layer.

## Trigger

Simulator testing confirmed: URLSession was downloading bytes and Rust was sending `DownloadReport.progress` updates (rev incrementing ~1/sec), but the episode row stayed visually `.notDownloaded` — no progress bar, no state change

## Decision

Added `applyDownloadOverlay` helper that cross-references `DownloadQueueSnapshot.active` items against projected episodes, overlaying `.queued`, `.downloading(progress:bytesWritten:)`, and `.failed(message:)` states. Called in both the full projection path and the snapshot-only fast path.

## Consequences

- Swipe-to-download now shows visible progress bars in episode rows
- Both full and fast (snapshot-only) projection paths correctly reflect download state
- Future changes to download state mapping must go through `applyDownloadOverlay`, not just `toEpisode`
- The `DownloadState` enum cases `.queued` and `.downloading` now actually occur in the UI layer

## Open Tail

- Progress indicator rendering precision (thin bar vs full) not yet validated on device

## Evidence

- transcript lines 1865-1895
- transcript lines 1914-1935
- transcript lines 2013-2037
- transcript lines 2060-2089

