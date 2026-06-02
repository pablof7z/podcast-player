---
title: Playback Engine (M1 Part 3 Engine Swap)
slug: playback-engine-m1-part3
summary: "The M1 Part 3 engine swap (AudioEngine → AudioCapability kernel bridge): PlaybackState patterns, streaming URLs, position persistence, segment-end advancement, item-end handling, audio report threading, and the observation loop fix."
tags:
  - playback
  - engine
  - audio
  - kernel-bridge
  - m1
volatility: warm
confidence: medium
created: 2026-05-29
updated: 2026-05-30
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# Playback Engine (M1 Part 3 Engine Swap)

> The M1 Part 3 engine swap (AudioEngine → AudioCapability kernel bridge): PlaybackState patterns, streaming URLs, position persistence, segment-end advancement, item-end handling, audio report threading, and the observation loop fix.

## Episode Streaming URL

The Rust `EpisodeSummary` includes `enclosure_url: Option<String>` projected from `Episode.enclosure_url`. The Swift `toEpisode` function builds the playback URL from: `downloadPath.flatMap { URL(fileURLWithPath: $0) }` (downloaded episodes) falling back to `enclosureUrl.flatMap { URL(string: $0) }` (streaming), falling back to `URL(string: "https://placeholder.invalid/\(id)")!` as a last-resort placeholder. The `AudioCommand.load` handler in `PlaybackState+AudioCallbacks.swift` uses the URL from the Rust-resolved `urlString` for non-downloaded episodes to ensure AVPlayer streams from the real RSS enclosure URL, not the placeholder. <!-- [^14943-5] -->


The setEpisode function must gate kernelDownload on the episode's downloadState being .notDownloaded or .failed. Calling it unconditionally triggers redundant download operations for episodes that are already downloaded, downloading, or queued. <!-- [^14943-38] -->
## attachKernel Observation Loop

The `kernelObservationTask` uses an apply-before-await pattern to prevent a `withObservationTracking` race condition. It calls `applyKernelState` at the top of each loop iteration before arming the observation with `withObservationTracking { _ = kernel.library; _ = kernel.podcastSnapshot } onChange: { continuation.resume() }`. This guarantees the latest state is applied regardless of whether the observation fires. Without this, the task may arm on an already-final value where `onChange` never fires, leaving the library empty. <!-- [^14943-6] -->

## Playback Position Advancement

Playback position was stuck at 0:00 due to the `Episode.enclosureURL` being set to `https://placeholder.invalid/{id}` for non-downloaded episodes. The fix was adding `enclosure_url` to both Rust's `EpisodeSummary` and Swift's mirror, so AVPlayer can stream from the real RSS enclosure URL. Verified live: position advanced 0:00 → 0:03 → 0:17 → 0:44 with the full player showing the scrubber at the correct position, -13:15 remaining, and the pause button active. <!-- [^14943-7] -->

## PlaybackState and Kernel Dispatch

`PlaybackState.play()` calls `engine.play()` and then dispatches `store?.kernelLoad(episodeID: episode.id)` to the Rust kernel. This is required so Rust's `PlayerActor` receives the `episode_id` to correlate audio reports for position writeback, played marking, and auto-advance. Without this, Swift-initiated plays are invisible to Rust. The `audio.commandHandler` closure captures the store via `[weak self]` and accesses `self.store?.episode(id: id)` inside the body — not via `[weak self, weak store = self.store]` which would capture a nil store at init time. <!-- [^14943-8] -->


Swift's markEpisodePlayed call, which handles side effects like delete-after-played and progress reset, must be gated on the autoMarkPlayedAtEnd setting — matching Rust's gate on auto_mark_played_at_end. Calling it unconditionally on natural end ignores the user's preference. <!-- [^14943-36] -->
## Audio Report Threading

`attachAudioReportChannel()` dispatches the `nmp_app_podcast_audio_report` FFI call to a background serial queue (`DispatchQueue(label: "podcast.audio-report", qos: .utility)`), not on MainActor. This prevents a deadlock when `ItemEnd` triggers `maybe_auto_advance`, which calls `dispatch_capability` → `SyncCapabilityBridge.handle` → `DispatchQueue.main.sync`. The follow-up `AudioCommand` is re-dispatched to `@MainActor` via `Task { @MainActor in ... }`. All three report channels (audio, download, voice) fire the `onSnapshotMaybeChanged` hook afterward for reactive state updates. <!-- [^14943-9] -->

## Seek and Skip Position Persistence

When paused, `seek(to:)`, `skipBackward`, and `skipForward` persist the new position to Rust's store via `store?.kernelPersistPosition(episodeID:positionSecs:)`. This dispatches `op:"persist_position"` with `episode_id` and `position_secs` — it writes directly to the store without returning an `AudioCommand`. The `kernelPersistPosition` function is distinct from `kernelSeek`, which only dispatches an audio command without persisting. <!-- [^14943-10] -->

## Segment-End Advancement

The `onPlayingTick` handler watches `currentSegmentEndTime`. When `position >= currentSegmentEndTime`, it pops the next item from the queue via `playNext(resolve:)` or pauses the engine if the queue is empty. The watch uses `[weak self]` to avoid retaining the playback state. When Rust auto-advances (via `ItemEnd`), the iOS queue is synced by popping the front whole-episode item in the `commandHandler` for `AudioCommand.load` if the loaded episode ID matches the queue front. <!-- [^14943-11] -->


The currentSegmentEndTime boundary must be set after setEpisode completes, not before. Setting it before causes bounded clips to play past their segment end because the boundary is applied to the wrong (prior) episode. <!-- [^14943-37] -->
## Item End and Sleep Timer

On natural item end, `handleEndOfItem()` in `AudioEngine+Observers.swift` emits both `onPauseEvent?(url, duration)` and `onItemEnd?(url)` — the pause flushes the exact final position before the item-end marks the episode as played. On sleep-timer end-of-episode, the sleep-timer path emits `onPauseEvent?(url, duration)` only (no auto-advance) and fires an `onSleepTimerEpisodeEnd` callback to explicitly call `store?.kernelMarkPlayed(episode.id)`. The `onPlayingTick` also calls `NowPlayingSnapshotStore.updatePosition(position, isPlaying: true)` to keep the widget in sync. <!-- [^14943-12] -->


On natural item end, Rust's apply_writeback must reset the stored position to 0 after marking the episode as played. Without this reset, the stored position remains at the episode's duration, causing replay to resume at the end. This is a Rust-side fix (Rust owns position via audio reports), applied unconditionally — a completed episode should always replay from the start. <!-- [^14943-35] -->

handle_load (the path the UI actually uses to play episodes via kernelLoad) now enqueues a download when the episode is not downloaded, mirroring handle_play's enqueue block. This consolidates download-on-play into the Rust load path and ensures restored episodes (not-downloaded, loaded from persistence) trigger downloads. A Rust test was added for the handle_load enqueue path. <!-- [^14943-75] -->

The sleep-timer end-of-episode rewind is now ordered correctly by emitting the Paused report with position 0 directly for the sleep-timer-end case, rather than racing a host-op rewind against the queued onPauseEvent. The old race condition saw the queued onPauseEvent(duration) overwrite the rewind back to duration after the host-op had already reset to 0. <!-- [^14943-78] -->
## See Also
- [[kernel-bridge-patterns|Kernel Bridge Patterns]] — related guide
- [[known-bug-patterns|Known Bug Patterns]] — related guide
- [[reactive-update-model|Reactive Update Model (No Polling)]] — related guide

