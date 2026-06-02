---
title: PlaybackState as Pure Renderer (M1.7)
slug: playbackstate-m1-pure-renderer
summary: PlaybackState is a pure renderer at 205 lines (≤300 limit). All business callbacks moved to Rust; only thin shell methods remain.
tags:
  - m1
  - playback
  - playbackstate
  - renderer
volatility: cold
confidence: medium
created: 2026-05-29
updated: 2026-05-29
verified: 2026-05-29
compiled-from: conversation
sources:
  - session:14943b9b-5bf3-4317-bc44-298a773bc75e
---

# PlaybackState as Pure Renderer (M1.7)

> PlaybackState is a pure renderer at 205 lines (≤300 limit). All business callbacks moved to Rust; only thin shell methods remain.

## M1.7 Limit

PlaybackState.swift must not exceed 300 lines. After the M1 Part 3 migration (#133), PlaybackState is a pure renderer at 205 lines — comfortably within the ≤300 limit. All business callbacks (onPersistPosition, onFlushPositions, onEnsureDownloadEnqueued, etc.) have been deleted; behavior has moved to Rust handlers. The remaining PlaybackState is a thin shell: play(), pause(), seek(to:), skip methods, and queue management that delegates to the kernel via kernelLoad, kernelPersistPosition, and kernelMarkPlayed. <!-- [^14943-33] -->

## What Was Deleted

The M1.5 callback deletion removed all on* business-logic callbacks from PlaybackState. These were the observer-style hooks that the old AudioEngine called to notify PlaybackState of playback events. With the kernel bridge, position writeback, auto-advance, and download enqueue all live in Rust handler functions. The Swift side only receives AudioCommand values via the audio.commandHandler and delegates to the engine. <!-- [^14943-34] -->
