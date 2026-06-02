---
title: M1 Codex Playback Regressions
slug: m1-codex-playback-regressions
summary: "Four playback regressions found by codex in the M1 stack: replay-starts-at-end, auto-mark-ignored, segment-boundary-too-early, and redundant re-download."
tags:
  - m1
  - playback
  - regressions
  - codex
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# M1 Codex Playback Regressions

> Four playback regressions found by codex in the M1 stack: replay-starts-at-end, auto-mark-ignored, segment-boundary-too-early, and redundant re-download.

## Bug 1: Replay Starts at End Position

When an episode completes naturally (ItemEnd), Rust's apply_writeback leaves the stored position at the episode's duration. Marking the episode as played does not reset position to 0. If the user replays the completed episode, the stored position causes playback to resume at the end. Fix: reset position to 0 unconditionally on natural ItemEnd completion — a completed episode should always replay from the start. This is fixed in Rust (position ownership) via a store.set_episode_position(ep_id, 0.0) call in the ItemEnd writeback path. <!-- [^14943-29] -->

## Bug 2: markEpisodePlayed Ignores autoMarkPlayedAtEnd

Swift's markEpisodePlayed is called unconditionally on natural episode end, but Rust's apply_writeback gates the mark-played behavior on the auto_mark_played_at_end setting. Swift must respect the same gate: call markEpisodePlayed only when autoMarkPlayedAtEnd is true. The setting is available on the PlaybackState's internal state. <!-- [^14943-30] -->

## Bug 3: Segment Boundary Set Before setEpisode

The currentSegmentEndTime segment boundary is set before setEpisode is called when enqueuing segments or playing next. This causes bounded clips to play past their segment end, missing the advancement trigger. Fix: set currentSegmentEndTime after setEpisode completes, so the segment boundary is applied to the currently loaded episode. <!-- [^14943-31] -->

## Bug 4: Redundant Re-Download

PlaybackState.setEpisode calls kernelDownload unconditionally, even for episodes that are already downloaded. This triggers redundant download operations. Fix: gate kernelDownload on the episode's downloadState being .notDownloaded or .failed — skip the download dispatch for already-downloaded, downloading, or queued episodes. <!-- [^14943-32] -->
