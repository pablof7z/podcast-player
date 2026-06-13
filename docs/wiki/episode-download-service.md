---
title: Episode Download Service
slug: episode-download-service
topic: data-persistence
summary: EpisodeDownloadService reserves a background URLSession identifier, but the AppDelegate hook is not currently wired.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:ce9e0cdb-a00d-4c13-ad7e-93e3dced2648
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
  - session:e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
  - session:1bfd020d-5183-458d-8f13-fda034490988
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
  - session:9833dc25-72f9-4d4f-98d9-df476ead3e6d
  - session:ede5e5c5-01cb-4985-aae5-6a4e1b09fc08
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
  - session:rollout-2026-05-10T10-27-27-019e10c8-ab1d-7523-8825-9bb1a52e6aac
  - session:rollout-2026-05-11T08-21-02-019e157b-4b15-77a0-8003-a3ae75cf8c26
  - session:rollout-2026-05-11T09-10-30-019e15a8-9588-70a1-99b0-f20d08ac91a4
  - session:rollout-2026-05-26T10-26-17-019e632d-5c5d-7bb3-8b90-fb176055c79d
---

# Episode Download Service

## Background URL Session

DownloadCapability.handleEventsForBackgroundURLSession guards on its own identifier and calls the completion handler immediately for other identifiers, rather than routing all events to the episode handler. Background URLSession handoff for downloads must be wired through AppDelegate into EpisodeDownloadService.

<!-- citations: [^0f3f2-33] [^e1ab0-4] [^rollo-86] [^rollo-110] -->
## Agent-Generated Episode Storage

Agent-generated podcast episodes are stored as local m4a files at Application Support/podcastr/agent-episodes/<episodeID>.m4a, not in the downloads/ directory that EpisodeDownloadStore checks. TranscriptIngestService.runAITranscription uses episode.downloadState to locate downloaded files rather than EpisodeDownloadStore.shared.exists() which checked the wrong directory.

<!-- citations: [^ce9e0-2] [^ede5e-6] -->
## Download State Fallback Bug

EpisodeDownloadStore.exists(for:) checks podcastr/downloads/ while DownloadCapability saves to Downloads/<id>.<ext>, causing on-device transcription to silently bail at the file-existence guard. apply_download_report emits DOWNLOAD_FINISHED with byte count and file path details even when the local file path is wrong (i.e., even with the path mismatch, the download event is still logged). PR #351 fixes the path mismatch by changing EpisodeDownloadStore.rootURL to Downloads/, so downloaded audio files are actually found by transcription and playback code. When an episode is not found in EpisodeDownloadStore but its downloadState is .downloaded, AudioEngine.load(_:) recomputes the file path via AgentGeneratedPodcastService.audioFileURL(episodeID:) before falling back to the stored enclosureURL, which may be a stale absolute file:// URL after iOS container path rotation. The Downloads/ path scheme in DownloadCapability is intentional for M4-Rust legacy migration and must not be changed. Offline/downloaded state can misrepresent availability if the local file disappears, causing offline users to tap a 'downloaded' episode and hit a network failure.

<!-- citations: [^ce9e0-3] [^ede5e-7] [^7e35e-6] [^rollo-88] -->
## Auto-Download Policy

AutoDownloadPolicy evaluation was dead Swift code (zero callers) and was deleted; the Rust kernel owns the auto-download decision via SetAutoDownload and episodes_to_auto_download. The kernel AutoDownloadPolicy stores only an enabled boolean, collapsing latestN/allNew variants. The 'Latest N' auto-download policy only selects from newly inserted episodes and never prunes older downloads, contrary to the implication that it acts as a retention cap. Auto-download evaluation is triggered by dispatching an AutoDownloadEvaluate action on both cold-start (via lifecycleForeground) and when auto-download is enabled for a podcast. The evaluation includes a current-library backfill scan, allowing episodes of an existing show to be downloaded when auto-download is toggled on. Cold-launch restore of the last-played episode must not trigger an eager auto-download enqueue. Wi-Fi-only auto-download behavior must persist queued episodes and drain them when Wi-Fi is available, rather than skipping them.

<!-- citations: [^14943-5] [^9833d-5] [^rollo-89] [^rollo-111] [^rollo-260] -->
## File Size Caching

The synchronous filesystem stat per downloaded episode (URL.resourceValues for fileSizeKey) on the main thread was eliminated by caching file_size_bytes in the Rust projection at download-completion time. <!-- [^14943-6] -->

## Download Pipeline

The episode download pipeline (swipe action, button action, kernel dispatch, Rust DownloadQueue, DownloadCapability) is fully wired end-to-end with no stubbed paths. PR #256 (unify episode + local-model downloads behind one kernel queue) is merged to main.

All episode download initiators (manual download, auto-download, deferred-wifi, and player-initiated) are routed through a single canonical start_episode_download helper that enforces the queue, concurrency control, and event logging. Auto-downloads are gated behind triage completion; archived episodes do not trigger notifications or downloads on the same cycle they were created in. (Previously: Episodes are downloaded automatically following app settings, superseded — see inbox-triage.)

<!-- citations: [^9833d-6] [^e1cfd-5] [^56e47-2] [^ede5e-4] -->
## Kernel Dispatch: Enclosure URL

Swift passes the enclosure URL directly in the kernel dispatch body so Rust does not need to look it up in its own PodcastStore, with Rust falling back to store lookup if no URL is provided. <!-- [^e1cfd-6] -->

## Kernel Download Episode Accessor

kernelDownload uses the canonical episode accessor `episode(id:)` on AppStateStore rather than `state.episodes`, because after the observation granularity refactor (PR #227), `state.episodes` is empty. <!-- [^e1cfd-7] -->

## Download State Overlay

Episode.downloadState gets overlayed from DownloadQueueSnapshot.active in both the full and fast projection paths, mapping .queued and .downloading states rather than only .downloaded/.notDownloaded. KernelModel exposes a `downloadSnapshot: DownloadQueueSnapshot?` property, updated on every accepted frame where downloads actually changed (via Equatable diff), serving as the always-fresh single source of download state. The `withObservationTracking` block in AppStateStore+KernelProjection includes `_ = kernel.downloadSnapshot` so the projection task re-runs when a download progress report lands. The snapshot-only fast path (`applyKernelSnapshotOnlyState`) calls `applyDownloadOverlay(active: kernel?.downloadSnapshot?.active)` using the fresh source rather than the hash-gated `podcastSnapshot.downloads`. Views read `episode.downloadState` directly instead of performing inline kernel-snapshot lookups or `live ?? persisted` fallback patterns. The domain model (`episode.downloadState.progress`) is kept current by a single write path, and views are dumb readers of that model. SwiftFormat reverts view-layer simplifications but leaves the architectural changes in `KernelModel.swift` and `AppStateStore+KernelProjection.swift` intact, and this does not break the fix since both the persisted and live values are now identical.

A case-sensitivity bug caused completion reports (uppercase UUIDs from Swift) to fail against lowercase Rust comparison, preventing downloads from marking as 'Downloaded'; this was fixed with case-insensitive matching. The Rust function episode_enclosure_url uses case-insensitive UUID matching, covering all callers (download start, play, completion/cancel, relaunch replay).

Swiping to download an episode shows a faint full-width bar (progress: 1.0, opacity 0.15) immediately in the .queued state. The .downloading progress bar has a minimum visible width of 8px. Swiping on an episode in .queued state shows a 'Cancel' action instead of 'Download'. Queued downloads are modeled in UI and state but never actually produced by the service, which transitions directly to downloading.

<!-- citations: [^56e47-1] [^ede5e-3] [^e1cfd-8] [^1bfd0-1] [^rollo-87] -->
## Byte Transfer Executor

Byte transfer stays in the platform executor (iOS URLSession, Android DownloadManager) because only background-configured platform sessions keep downloading while the app is suspended; Rust in-process is frozen. DownloadCapability saves files to AppSupport/Downloads/<episodeID>.<ext>.

<!-- citations: [^e1ab0-5] [^ede5e-8] -->
## Task Description Routing

Swift DownloadCapability encodes kind in taskDescription (bare id for episodes = backward-compatible, local_model:<id> for models) and decodes it on completion to route files correctly. <!-- [^e1ab0-6] -->

## Download Resume Behavior

Episode downloads resume from the saved byte offset using NSURLSessionDownloadTaskResumeData persisted to disk, while model downloads restart from scratch because LocalModelDownloadManager never captures or persists the resume blob. The unified download manager gives models resume/retry/background support for free by inheriting the episode DownloadCapability's existing resume implementation. <!-- [^e1ab0-7] -->

## Download Robustness

Episode downloads are not affected by the model download bug — they match by episodeID (taskDescription), move the file correctly, and have proper urlSessionDidFinishEvents. In-flight downloads are preserved (not clobbered back to .notDownloaded) when the view re-appears and recomputes state from disk. <!-- [^e1ab0-8] -->

## Download Progress & Pause Reports

DownloadCapability emits an immediate 0-byte progress report after task.resume() so Rust transitions from .queued to .downloading without waiting for the D8 throttle gate. OS-driven URLSession cancellations (NSURLErrorCancelled) emit a .paused report to Rust with the bytes downloaded, detected via map entry presence distinguishing OS-driven from command-driven cancels. <!-- [^ede5e-5] -->

## Downloads Manager Screen

A Downloads Manager screen exists at Settings > Library > Downloads, showing Active & Queued, Failed, and Downloaded sections with summary counts, per-episode progress, row actions (start, retry, cancel, clear failed state, delete), and bulk actions (cancel active, delete downloaded). The EpisodeDownloadService singleton is attached at store startup so the Downloads Manager and background download callbacks share the same store without relying on a row action being tapped first. <!-- [^rollo-35] -->

## File Organization

EpisodeDownloadService.swift must stay under the 300-line soft limit by splitting auto-download policy methods into a companion extension file (EpisodeDownloadService+AutoDownload.swift). <!-- [^rollo-112] -->
