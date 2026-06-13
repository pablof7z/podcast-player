---
type: episode-card
date: 2026-05-28
session: f1804b3d-52ea-4a3f-bbf2-608cef7c7468
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f1804b3d-52ea-4a3f-bbf2-608cef7c7468.jsonl
salience: architecture
status: superseded
subjects:
  - podcast-tui-snapshot-delivery
  - nmp-update-bridge
supersedes: []
related_claims: []
source_lines:
  - 1294-1297
  - 1392-1392
  - 2497-2520
captured_at: 2026-06-12T12:52:36Z
---

# Episode: TUI snapshot delivery: replace FlatBuffers-JSON mismatch with native Rust push-signal

## Prior State

The TUI's NmpUpdateBridge callback received binary FlatBuffers frames from the kernel but attempted to parse them as UTF-8 JSON strings, which always failed with 'expected value at line 1 column 1'. No snapshot data ever reached the UI — subscribe actions appeared to silently do nothing.

## Trigger

User reported that subscribing to a valid RSS feed (Huberman Lab) showed only 'subscribing to' with no result. Root-cause analysis revealed the binary-vs-JSON decode failure. Initial fix attempt (polling nmp_app_podcast_snapshot JSON) was rejected by user: 'nobody should be polling and nobody should be using json!'

## Decision

Adopted push-based architecture using native Rust types: (1) NmpEvent became a lightweight unit signal — the callback no longer attempts to decode binary payloads; (2) PodcastHandle gained an update() method returning PodcastUpdate directly without JSON serialization; (3) main.rs calls runtime.podcast_update() on each UiEvent::Nmp signal and applies the typed PodcastUpdate to AppState. This mirrors the iOS/Android proven path but bypasses JSON entirely.

## Consequences

- TUI no longer depends on FlatBuffers decode or JSON parse for snapshot delivery
- NmpEvent.payload field is no longer the data carrier — it is a change-signal only
- PodcastUpdate struct is now a shared contract between nmp-app-podcast and podcast-tui
- Future TUI features get typed Rust access to all PodcastUpdate fields without manual JSON extraction
- The snapshot_cache/rev mechanism in PodcastHandle is reused for change detection without serialization overhead

## Open Tail

- PodcastUpdate and its projection types must remain re-exported from nmp-app-podcast's public API for TUI consumption
- The module visibility of ffi::snapshot needed adjustment (was private, caused E0603 compile error)

## Evidence

- transcript lines 1294-1297
- transcript lines 1392-1392
- transcript lines 2497-2520

