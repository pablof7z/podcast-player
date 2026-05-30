---
title: M1 Queue Unification (Dual-Queue P1 Fix)
slug: m1-queue-unification
summary: "Codex P1 fix: dual-queue gap where UI-queued episodes never auto-advanced; resolved by unifying on the canonical PlaybackQueue."
tags:
  - migration
  - playback
  - rust
  - codex
volatility: cold
confidence: medium
created: 2026-05-30
updated: 2026-05-30
verified: 2026-05-30
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# M1 Queue Unification (Dual-Queue P1 Fix)

> Codex P1 fix: dual-queue gap where UI-queued episodes never auto-advanced; resolved by unifying on the canonical PlaybackQueue.

## Overview

Codex pass 2 of the M1 stack discovered that the UI queue (podcast.queue, routed to PlaybackQueue via QueueActionModule) and the auto-advance queue (PlayerActor.queue, populated only by podcast.player Enqueue) were two separate queues. Since #133 deleted Swift's playNext, auto-advance was broken: UI-queued episodes never auto-advanced. The PlaybackQueue was designated as canonical (the snapshot builds from handle.queue, which is PlaybackQueue) and the fix redirected maybe_auto_advance to pop from the canonical queue. [^14943-51]

## Fix

The maybe_auto_advance function was modified to pop the next episode ID from handle.queue (the canonical PlaybackQueue) instead of the actor's internal PlayerActor.queue. The actor retains auto_play_next and stage_load for episode load management. The vestigial PlayerActor.queue was deferred to a tracked BACKLOG item for future cleanup. [^14943-52]

## Verification

Rust tests remained at 705 pass after the queue fix. The fix was verified at the code level: UI enqueue routes to podcast.queue -> QueueActionModule -> handle.queue; snapshot builds from handle.queue via build_podcast_update; and maybe_auto_advance now pops from handle.queue. All three now use the same PlaybackQueue instance, closing the dual-queue gap. [^14943-53]

## See Also

