---
title: Episode Audit Events
slug: episode-audit-events
topic: data-persistence
summary: "The kernel-owned event log JSON must decode directly into the Swift `EpisodeAuditEvent` model with keys: `id`, `episodeID`, `timestamp` (ISO8601 no-fractional),"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-07
updated: 2026-06-10
verified: 2026-06-07
compiled-from: conversation
sources:
  - session:9833dc25-72f9-4d4f-98d9-df476ead3e6d
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
  - session:681fa743-322c-4b1a-8e99-81a97aa1a904
  - session:38f8143c-c90d-49e3-a8fa-8d5ca17ac319
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
---

# Episode Audit Events

## Episode Audit Event Model

The kernel-owned event log JSON must decode directly into the Swift `EpisodeAuditEvent` model with keys: `id`, `episodeID`, `timestamp` (ISO8601 no-fractional), `kind` (dotted rawValue), `severity`, `summary`, and `details` (array of `{label, value}`). Episode ID keys in the event log are normalized to lowercase to unify Rust's lowercase `Uuid` with Swift's uppercase `uuidString`. PR #373 fixes a UUID case mismatch where iOS dispatches uppercase UUID.uuidString but the kernel stores lowercase, causing the case-sensitive lookup in episode_playback_info to fail before stage_load set episode_id, which left now_playing/widget idle during playback. (Previously: Episode ID keys in the event log are normalized to lowercase to unify Rust's lowercase `Uuid` with Swift's uppercase `uuidString`.) The event log infrastructure persists per-episode JSON files at episode-events/<id>.json. Episode events are capped at MAX_EVENTS_PER_EPISODE = 200, and hydrate_events loads from disk on first touch per session.

Episode SQLite uses delta row snapshots for single-episode changes instead of rewriting the full sidecar. Metadata JSON plus episode SQLite changes are committed atomically together. <!-- [^rollo-44] -->

<!-- citations: [^9833d-2] [^7e35e-2] [^38f81-2] -->
## Episode Audit Event Pipeline Kinds

The Rust kernel records pipeline events for the full episode lifecycle: download (requested/started/finished/failed), transcript (attempt/ready/failed/skipped), chapters (ready), and ads (ready). PodcastStore.record_transcript_skip(episode_id, reason) emits a transcript.skipped event that is idempotent (collapses repeat identical skips) and does not bump the rev counter, since a skip changes no projected state. The "skipped" transcript status is intercepted in handle_set_episode_transcript_status before reaching set_transcript_status, so it emits an event without mutating durable transcript state.

Episode Diagnostics must include a Pipeline configuration panel that plainly states what will or will not happen to an episode before any events are read, e.g. 'Won't transcribe automatically — AI transcription fallback is OFF' or 'Will transcribe on-device with Apple on-device once downloaded'. Every transcript event must name the service or provider behind it (e.g. 'Transcribing audio · ElevenLabs Scribe', 'Transcript ready · Apple on-device'). Chapter events must name the model used, honestly indicating 'equal-length fallback' when the model was unavailable instead of labeling it 'AI'. Episode Diagnostics must emit playback events (playback started and playback completed) that were previously invisible. Episode Diagnostics must emit clip created, clip exported, and clip failed events. Episode Diagnostics must emit search-indexing succeeded and search-indexing failed events. <!-- [^681fa-3] -->

<!-- citations: [^9833d-3] [^7e35e-3] -->
## FFI Integration

The redundant Swift `EpisodeAuditLogStore` is deleted, and the Diagnostics view is rewired to read events directly from the kernel via a lazy FFI getter. The new FFI getter for episode events is declared in the hand-maintained `App/Sources/Bridge/NmpCore.h` header. The nmp_app_podcast_episode_events FFI returns an empty JSON array when the handle or episode_id is invalid, the lock is poisoned, or the episode has no log, per D6 degrade-silently policy (no panics across FFI). EpisodeAuditLogView.loadEvents() calls store.kernelEpisodeEvents(episode.id) and returns an empty-array placeholder message when no events exist: "No events recorded yet. Trigger a download or transcription to populate the log."

<!-- citations: [^9833d-4] [^7e35e-4] -->

## Episode Audit Event Tests

PR #352 adds two Rust tests: one pinning the transcript.skipped event wire shape and one verifying the idempotency dedup in the directly-tested PodcastStore method. <!-- [^7e35e-5] -->
