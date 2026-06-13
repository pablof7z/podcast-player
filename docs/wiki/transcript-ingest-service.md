---
title: Transcript Ingest Service
slug: transcript-ingest-service
topic: stt-providers
summary: "TranscriptIngestService.ingest accepts an optional `forceProvider: STTProvider?` parameter that skips the publisher-transcript path and bypasses the `autoFallba"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-12
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:9f2d26f1-3e71-46b0-83d8-cc9895be3a8e
  - session:9833dc25-72f9-4d4f-98d9-df476ead3e6d
  - session:ede5e5c5-01cb-4985-aae5-6a4e1b09fc08
  - session:7e35e451-81d2-4832-8c6e-34d44fc29e12
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
  - session:rollout-2026-05-11T09-10-31-019e15a8-97f5-7fc2-9daf-4c834d1999b0
---

# Transcript Ingest Service

## TranscriptIngestService.ingest

The transcription pipeline is no longer purely HTTP-based; it includes an on-device apple_native provider (AppleNativeSTTClient.swift using SpeechTranscriber and SpeechAnalyzer on the Apple Silicon NPU) alongside HTTP-based providers (ElevenLabs/AssemblyAI), with local storage in TranscriptStore. (Previously: NIP-90 does not exist; the transcription pipeline is purely HTTP-based (ElevenLabs/AssemblyAI/Apple STT) with local storage in TranscriptStore, superseded — see apple-native-stt.) TranscriptIngestService.ingest accepts an optional `forceProvider: STTProvider?` parameter that skips the publisher-transcript path and bypasses the `autoFallbackToScribe` gate. TranscriptionQueue has an explicit fallback policy and documents TranscriptIngestService as the authoritative runtime ingestion path.

Transcriptions are generated automatically after an episode is downloaded, with download completion triggering a re-entry into the `ingest()` method to kick off transcription/identification. The `ingest()` method includes a readiness guard so the post-download hook is safe to fire unconditionally without race conditions.

TranscriptIngestService.ingest() skip conditions now emit idempotent transcript.skipped events via PodcastStore.record_transcript_skip without bumping the rev counter or mutating durable state, so the Diagnostics sheet can explain why transcription was skipped. (Previously: TranscriptIngestService.ingest() has multiple silent-return guards (appStore nil, inFlight dedup, episode nil, already-ready, category opt-out, AI-transcription-off, forced-provider-no-key, on-device-no-file) that emit no events, making the Diagnostics sheet unable to explain why transcription didn't proceed, superseded — see episode-audit-events.) RAGService.appStore is a weak reference that can become nil, causing TranscriptIngestService.ingest() to silently return without emitting any event.

The on-device-no-file guard in TranscriptIngestService.runAITranscription (line 221-223) only surfaces as a skip event on explicit user-initiated retries, not on speculative auto-ingest paths, to avoid spam from feed-refresh re-ingests.

A path mismatch between DownloadCapability (AppSupport/Downloads/) and EpisodeDownloadStore (AppSupport/podcastr/downloads/) causes TranscriptIngestService to silently skip appleNative transcription at line 221.

A publish hook for transcripts should be placed in TranscriptIngestService.swift lines 325-329, right after store.save(transcript), using the fire-and-forget Task { @MainActor } pattern.

A consume hook for Nostr transcripts should be inserted as Path A.5 in TranscriptIngestService.swift lines 194-197, between the publisher RSS fetch fall-through and the STT fallback.

<!-- citations: [^9f2d2-10] [^9f2d2-11] [^7f076-11] [^9f2d2-9] [^9833d-8] [^ede5e-9] [^7e35e-13] [^rollo-121] -->
## TranscriptSource and TranscriptState.Source

TranscriptSource and TranscriptState.Source enums both need a dedicated .nostr case that must not repurpose the existing .other case (which is used by agent-TTS). <!-- [^9f2d2-12] -->

Chapters are generated as a side-effect of persistAndIndex in TranscriptIngestService, which only runs after successful transcription. <!-- [^ede5e-10] -->

## Overview

Apple Native STT does not support speaker diarization and produces a flat transcript with no speaker IDs, so not all pulled transcripts carry speaker labeling; ElevenLabs is used when transcripts are not available. (Previously: The podcast player pulls timestamped transcripts with speaker labeling, using ElevenLabs when transcripts are not available. <!--  -->, superseded — see apple-native-stt.)
