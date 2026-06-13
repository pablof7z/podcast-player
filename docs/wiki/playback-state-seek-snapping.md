---
title: Playback State Seek Snapping
slug: playback-state-seek-snapping
topic: playback
summary: PlaybackState.seekSnapping is a degenerate alias for seek
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
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
  - session:rollout-2026-05-11T08-21-01-019e157b-4863-7563-a43b-8405491d88a1
  - session:rollout-2026-05-11T09-10-30-019e15a8-9491-7d33-9bbf-ee806e2f875c
  - session:rollout-2026-05-17T17-40-02-019e3661-3d9a-76d3-a4a5-f5779f6a0ee8
---

# Playback State Seek Snapping

## seekSnapping

PlaybackState.seekSnapping is a degenerate alias for seek. Transcript-snapping is deferred (Lane 3). <!-- [^0f3f2-56] -->

## Playback Queue Routing

The Up Next queue read/write split bug is fixed: enqueue, dequeue, clear_queue, and play_next ops now route to the canonical PlaybackQueue instead of the separate PlayerActor.queue that was never rendered. <!-- [^55bed-10] -->

## CarPlay Chapter Visibility

CarPlay chapter visibility and chapter lists resolve from the live Rust store projection (store.episodes) rather than the stale PlaybackState snapshot; the poll tracker fires a refresh when navigableChapterCount changes on the same episode. <!-- [^55bed-11] -->

## Cold Restart Position Safety

On cold restart, a lock-screen Play command dispatches kernelLoad before starting audio; PR #373 fixes a UUID case mismatch where iOS dispatched uppercase UUID.uuidString but the kernel stored lowercase, causing the case-sensitive episode_playback_info lookup to fail before stage_load set episode_id and leaving now_playing/widget idle. (Previously: On cold restart, a lock-screen Play command dispatches kernelLoad (staging the restored episode in Rust) before starting audio, preventing position and played-state from being lost. <!--  -->, superseded — see episode-audit-events.)

## External Play Routing

External-play routes through the kernel while handing the player a transient in-memory Episode for synchronous playback, using the same pattern as AgentTTSComposer. <!-- [^55bed-13] -->

## Playback Command Routing

Playback commands (remote controls, sleep timer) route through PlaybackState persistence/widget/loop side effects rather than calling AudioEngine directly. Remote controls must route through PlaybackState so seek/pause/skip/play keep persistence, flush, and snapshot side effects. PlaybackState should own remote-command and sleep-timer actions, or AudioEngine should emit command events that PlaybackState handles through one play/pause/seek path.

<!-- citations: [^rollo-47] [^rollo-79] [^rollo-126] -->
## Ad Segment Detection

PlaybackState.adSegments must be updated after async detection completes, or the cache must be replaced with a resolver/versioned store read. <!-- [^rollo-80] -->

## Queue Reconciliation

playNext must prune stale queue IDs until it finds a resolvable episode, preventing autoplay from stalling behind a single stale queue head item. (Previously: Queue pruning should happen at sheet/root appearance, or PlaybackState should expose a `resolvedQueue` reconciliation API. <!--  -->, superseded — see audio-engine.)

## Centralized Playback Formatters

Skip glyph support, remote-supported playback rates, and chapter clock time formatting should be centralized into `SkipGlyph`, `PlaybackRate.remoteSupportedRates`, and `PlayerTimeFormat.chapterClock`. <!-- [^rollo-82] -->

## Position Observation Hygiene

Playing/BufferingProgress audio ticks do not bump the global kernel rev; their now_playing state rides an inline AudioReportResponse payload so the scrubber/Dynamic Island/lock screen stay live without triggering a full-library rebuild. (Previously: Playback position ticks must not invalidate broad UI; `positionCache`, `positionFlushTask`, and `lastPositionFlush` must be moved behind a non-observable helper or marked observation-ignored. <!--  -->, superseded — see audio-engine.)
