---
type: episode-card
date: 2026-06-10
session: 681fa743-322c-4b1a-8e99-81a97aa1a904
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/681fa743-322c-4b1a-8e99-81a97aa1a904.jsonl
salience: architecture
status: active
subjects:
  - episode-events-ffi
  - ffi-boundary
  - diagnostics-pipeline
supersedes: []
related_claims: []
source_lines:
  - 1690-1691
  - 1713-1725
  - 2239-2245
captured_at: 2026-06-12T13:42:09Z
---

# Episode: New generic FFI enables Swift-to-kernel event recording for any pipeline stage

## Prior State

Episode diagnostic events could only originate from the Rust kernel. Swift-side lifecycle transitions — playback started/completed, clip created/exported, transcript indexing — were invisible in the diagnostics log because there was no mechanism for Swift to push events into the kernel's event store.

## Trigger

Need to surface the full episode pipeline (playback, clips, indexing) in diagnostics, but these transitions happen in Swift (AudioCapability, AppStateStore+Clips, TranscriptIngestService), not in the kernel.

## Decision

Created a generic `nmp_app_podcast_record_episode_event` FFI function that accepts episode ID, event kind string, severity, and an arbitrary details JSON blob. Swift calls this from AppStateStore+KernelActions via a new `kernelRecordEpisodeEvent` wrapper. This replaces per-event FFI additions with a single extensible channel.

## Consequences

- Any Swift lifecycle transition can now appear in diagnostics without kernel-side schema changes
- New event kinds are just string constants in Swift (playback.started, playback.completed, clip.created, clip.exported, transcript.indexed, transcript.index_failed)
- The FFI is exported in the dylib and verified present in both sim and device builds
- Future: the event kind string namespace is currently informal; may need canonicalization if event types grow

## Open Tail

- Event kind strings are defined ad-hoc in EpisodeAuditEvent.Kind — no enforcement against typos across the Swift/Rust boundary

## Evidence

- transcript lines 1690-1691
- transcript lines 1713-1725
- transcript lines 2239-2245

