---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - snapshot-projections
  - domain-payload-builders
  - perf-serialization
supersedes:
  - 2026-06-13-1-full-library-json-re-serialization-on
related_claims: []
source_lines:
  - 30-57
  - 7977-8000
  - 8015-8054
  - 8090-8098
captured_at: 2026-06-13T02:56:17Z
---

# Episode: Slice-local domain payload builders kill 1 Hz whole-library rebuild

## Prior State

Every actor tick re-serialized the entire podcast library (all podcasts × all episodes) via build_podcast_update → build_snapshot_payload. The rev-gated cache existed but was defeated because rev bumped on essentially every command dispatch, causing 57% CPU in serde_json and 14.6 GB memory footprint.

## Trigger

Sampling process 21680 showed 1,633/2,856 samples (~57%) in build_snapshot_payload → serde_json::to_string. The cache only helps when rev is stable, but commands bump rev on every tick, making the cache worthless for hot paths like playback.

## Decision

Replaced the monolithic build_podcast_update fan-in with per-domain slice-local payload builders (build_playback_payload, build_social_payload, etc.), each gated on its own domain_revs.X counter so a playback tick only serializes playback data. Byte-identity enforced via a shared episode_summary helper used by both the library and queue paths.

## Consequences

- A playback tick no longer touches library/episodes data — only the playback domain is serialized.
- Opus review caught a byte-divergence in build_queue_rows_from_store (hardcoded empty fields vs full EpisodeSummary) that the single golden fixture (empty queue) missed; fixed by extracting shared episode_summary helper.
- New regression test queue_row_byte_identical_to_full_snapshot_for_content_rich_episode enforces output equivalence for non-empty queues.
- Golden byte-identity test remains the safety gate for all future projection changes.

## Open Tail

*(none)*

## Evidence

- transcript lines 30-57
- transcript lines 7977-8000
- transcript lines 8015-8054
- transcript lines 8090-8098

