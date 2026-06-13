---
type: episode-card
date: 2026-06-08
session: ede5e5c5-01cb-4985-aae5-6a4e1b09fc08
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/ede5e5c5-01cb-4985-aae5-6a4e1b09fc08.jsonl
salience: root-cause
status: superseded
subjects:
  - episode-download-store
  - download-capability
  - transcription-pipeline
  - audio-engine
supersedes: []
related_claims: []
source_lines:
  - 1861-1939
  - 2267-2336
  - 2549-2571
captured_at: 2026-06-12T13:33:19Z
---

# Episode: Download path mismatch broke transcription, audio, and storage

## Prior State

EpisodeDownloadStore.rootURL resolved to AppSupport/podcastr/downloads/ while DownloadCapability.downloadsDirectory() saved files to AppSupport/Downloads/. The two paths never agreed, so EpisodeDownloadStore.exists(for:) always returned false for every downloaded episode.

## Trigger

User reported 'downloading a podcast doesn't do ANYTHING' — investigation traced TranscriptIngestService.runAITranscription line 221 (appleNative guard exits silently when exists() is false) to the path mismatch. Simulator filesystem confirmed: files present in Downloads/, podcastr/downloads/ empty.

## Decision

Unified EpisodeDownloadStore.rootURL to AppSupport/Downloads/ (capital D), matching DownloadCapability.downloadsDirectory(). The DownloadCapability+Storage.swift comment explicitly states this path is intentional for M4-Rust legacy migration, so EpisodeDownloadStore must conform rather than the reverse.

## Consequences

- Transcription (appleNative STT) will now find downloaded files and start processing instead of silently exiting
- AudioEngine will play local files instead of streaming over network
- StorageSettingsView will show correct download sizes
- ClipAudioComposer and ClipVideoComposer will find episode files for clip generation
- AgentTTSComposer will resolve local URLs correctly
- No migration needed for podcastr/downloads/ since that directory was always empty
- Resume-data paths remain consistent (DownloadCapability manages its own .resume/ subdir under Downloads/)

## Open Tail

- Verify end-to-end: download → transcription → chapter generation pipeline works with the corrected path
- EpisodeDownloadStore.resumeDataURL(for:) still uses rootURL/<uuid>.resume while DownloadCapability uses Downloads/.resume/<id>.data — these are separate resume mechanisms, not a conflict, but worth confirming

## Evidence

- transcript lines 1861-1939
- transcript lines 2267-2336
- transcript lines 2549-2571

