---
title: Podcast State Management
slug: podcast-state-management
topic: podcast-state-management
summary: The system distinguishes between durable state changes (such as completion or cancellation) and transient progress updates to optimize global library re-project
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-04
updated: 2026-06-06
verified: 2026-06-04
compiled-from: conversation
sources:
  - session:56e47844-b4ff-4402-9528-c704eade1d7b
  - session:deb49f4f-f275-419a-ab1c-b68c123af73b
---

# Podcast State Management

## State Management Architecture

The system distinguishes between durable state changes (such as completion or cancellation) and transient progress updates to optimize global library re-projections.

The Rust kernel serves as the Single Source of Truth (SSOT) for application state. It manages these distinctions by determining whether a change requires a global revision bump.
The `nmp_app_podcast_download_report` FFI function returns a JSON object containing a `durable_changed` field; the Rust kernel only increments the global podcast revision when this field is true, rather than on every progress tick.

To optimize performance, Rust maintains a `snapshot_cache` that returns cached JSON whenever the revision (`rev`) remains unchanged. 

On the Swift side, `nowPlaying` and `downloadSnapshot` are treated as separate observation targets to prevent position updates from churning lists. The application updates a narrow `downloadSnapshot` and applies a row-level overlay during progress ticks.
A full library pull and re-projection are performed only when the `durable_changed` flag is received.
The `libraryGeneration` provides an O(1) fast path to skip episode rebuilds when only the snapshot or identity changed.

<!-- citations: [^56e47-2] [^deb49-7] -->
