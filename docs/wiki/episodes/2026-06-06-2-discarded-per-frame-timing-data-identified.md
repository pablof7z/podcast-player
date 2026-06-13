---
type: episode-card
date: 2026-06-06
session: 57b63f46-0a23-4efc-b087-0a521300d906
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/57b63f46-0a23-4efc-b087-0a521300d906.jsonl
salience: root-cause
status: active
subjects:
  - discarded-timing-data
  - snapshot-pull-perf
supersedes:
  - 2026-06-06-1-in-app-ffi-main-thread-performance
related_claims: []
source_lines:
  - 278-287
  - 387-414
  - 440-464
  - 1241-1252
captured_at: 2026-06-12T13:20:10Z
---

# Episode: Discarded per-frame timing data identified as root cause of observability gap

## Prior State

The C callback (nmpUpdateCallback) and PodcastHandle already computed decodeMicros and payloadBytes per push-frame, and the main-thread apply path had os_signpost intervals — but these metrics were consumed nowhere and provided no on-device surface.

## Trigger

Investigation of the FFI bridge code revealed that timing data was computed per frame in the callback but thrown away (line ~281: 'these are thrown away, consumed nowhere'). The podcastSnapshot() synchronous pull ran a full-library JSON decode on the main thread with no timing visibility.

## Decision

Wire the already-computed timing data into PerfMetrics.record calls (push-frame decode, dispatch, snapshot pull) and add manual defer-timed segments for main-thread apply and projection. Surface all via the Performance HUD.

## Consequences

- Previously discarded per-frame decode timing and payload size are now persisted and viewable on-device
- Snapshot pull confirmed as the main-thread blocking culprit: 14.3ms peak for the O(N) full-library decode
- Future perf work can measure before optimizing — the peer's off-main snapshot decode effort now has a baseline

## Open Tail

*(none)*

## Evidence

- transcript lines 278-287
- transcript lines 387-414
- transcript lines 440-464
- transcript lines 1241-1252

