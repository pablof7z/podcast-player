---
title: M1 Codex Round-3 Fixes
slug: m1-codex-round3-fixes
summary: "Four localized P2 logic nits from codex pass 3: handle_load enqueue, ordered sleep-timer rewind, stale queue-head skip, and paused chapter persistence."
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

# M1 Codex Round-3 Fixes

> Four localized P2 logic nits from codex pass 3: handle_load enqueue, ordered sleep-timer rewind, stale queue-head skip, and paused chapter persistence.

## Overview

Codex pass 3 on the converged M1 integration found four localized P2 logic nits. All were addressed in a single round of fixes before the final codex approval. These were all bugs in the M1 round-2/3 fixes themselves, not the original #133 code. [^14943-54]

## Fix 1: handle_load Download Enqueue

handle_load (the path UI play actually uses via kernelLoad) stage-loads and dispatches an AudioCommand.Load but never enqueues a download. This meant restored episodes (not-downloaded, loaded from persistence) would skip the download enqueue. The fix mirrors handle_play's download-enqueue block into handle_load, consolidating the download-on-play rule in the Rust load path. A Rust test was added for the handle_load enqueue path. [^14943-55]

## Fix 2: Ordered Sleep-Timer Rewind

The sleep-timer end-of-episode path was racy: handleEndOfItem emitted onPauseEvent(url, duration) on a background queue, then the host-op rewind set position to 0 on main. The queued onPauseEvent ran after, overwriting position back to duration. The fix emits the Paused report with position 0 directly for the sleep-timer-end case and drops the racy host-op rewind entirely. [^14943-56]

## Fix 3: Stale Queue Head Skip

maybe_auto_advance popped exactly once, but a deleted/stale episode at queue head would cause it to advance to a deleted entry and stop. The old Swift playNext looped past stale heads. The fix makes maybe_auto_advance loop, skipping stale queue heads until it finds a valid next episode or the queue is empty. [^14943-57]

## Fix 4: Paused Chapter Jump Persistence

The chapter-jump path called engine.seek directly on chapter boundaries, bypassing PlaybackState.seek(to:) which persists position on pause. The fix routes chapter jumps through PlaybackState.seek(to:) to ensure the new position is stored in Rust even when paused. [^14943-58]

## See Also

