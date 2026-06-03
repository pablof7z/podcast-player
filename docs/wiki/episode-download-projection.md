---
title: Episode Download Projection
slug: episode-download-projection
summary: Episode projection maps `DownloadQueueSnapshot.active` status onto `Episode.downloadState` so that `.queued` and `.downloading` states are represented in the UI
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
  - session:1bfd020d-5183-458d-8f13-fda034490988
---

# Episode Download Projection

## Download State Mapping

Episode projection maps `DownloadQueueSnapshot.active` status onto `Episode.downloadState` so that `.queued` and `.downloading` states are represented in the UI rather than only `.downloaded` or `.notDownloaded`. The `EpisodeSummary.toEpisode()` projection maps only `.downloaded` or `.notDownloaded` for `downloadState`, ignoring `.queued` and `.downloading` states from `DownloadQueueSnapshot`. The `applyDownloadOverlay` helper overlays `.queued` and `.downloading` states from `DownloadQueueSnapshot.active` onto `Episode.downloadState` in both the full projection path and the snapshot-only fast path. `KernelModel` provides a `downloadSnapshot` property that updates on every accepted frame where downloads changed, serving as the always-fresh source of download state. The `withObservationTracking` block in `AppStateStore+KernelProjection` observes `kernel.downloadSnapshot` so the projection task re-runs when a progress report lands. `applyKernelSnapshotOnlyState` calls `applyDownloadOverlay` with active data from `kernel.downloadSnapshot` rather than the hash-gated `podcastSnapshot.downloads`. `KernelModel.podcastSnapshot` is intentionally hash-gated and excludes `d.progress` from its content hash so list views do not re-render at download frequency. The `applyDownloadOverlay` method runs on every download progress tick via `onSnapshotMaybeChanged`, updating `AppStateStore.episodes` with the fresh snapshot so that `episode.downloadState.progress` always carries the live value from the fresh download snapshot. Views must read `episode.downloadState` directly instead of using a live ?? persisted fallback pattern to read progress from a kernel snapshot. One write path keeps the domain model current and views act as dumb readers. The ungated `kernel.snapshot` must be used instead of the hash-gated `kernel.podcastSnapshot` for reading live download progress in views. The `onSnapshotMaybeChanged` handler must trigger an episode update path that is separate from the hash-gated `withObservationTracking` loop. The `kernelDownload` function looks up episodes via the canonical `episode(id:)` accessor on `AppStateStore`, not via `state.episodes`.

<!-- citations: [^e1cfd-14] [^e1cfd-17] [^1bfd0-1] [^1bfd0-2] -->
## See Also

