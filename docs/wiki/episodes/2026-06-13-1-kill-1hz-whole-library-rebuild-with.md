---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - snapshot-projections
  - domain-revs
  - episode-summary
supersedes:
  - 2026-06-13-1-slice-local-domain-payload-builders-kill
related_claims: []
source_lines:
  - 30-57
  - 134-154
  - 161-170
  - 7905-8054
captured_at: 2026-06-13T03:37:30Z
---

# Episode: Kill 1Hz whole-library rebuild with slice-local domain payload builders

## Prior State

build_snapshot_payload re-serializes the entire podcast library (all podcasts × all episodes) via serde_json::to_string on every actor tick when any domain changes. A rev-gated JSON cache exists but is defeated because the monolithic rev bumps on every state change (comments, feed fetch, knowledge, agent notes, etc.), making the fast path unreachable. 57% of CPU samples sit in serialization; physical footprint 14.6GB.

## Trigger

CPU profile of process 21680 showed 1,633/2,856 samples (~57%) in build_snapshot_payload → serde_json::to_string, with format_escaped_str as the leaf hotspot. Inspection of the rev-gated cache confirmed it was correct but defeated by per-tick rev bumps from unrelated domain mutations.

## Decision

Replace monolithic build_podcast_update with slice-local domain payload builders, each gated on its own domain_revs field so only the changed domain is re-serialized per tick. The full-library path remains for pull/golden but is no longer called on every tick. A shared episode_summary helper guarantees byte-identity between library and queue paths (by construction, not field-by-field copying).

## Consequences

- Opus review caught a byte-divergence bug: the initial slice-local queue builder hardcoded episode fields (description, chapters, ai_categories, etc.) to empty, diverging from the library path for any real episode. Fixed by extracting shared episode_summary helper used by both paths.
- New regression test queue_row_byte_identical_to_full_snapshot_for_content_rich_episode enqueues an episode with HTML description, chapters, and transcript, asserting byte-equality against build_podcast_update.
- Golden fixture untouched (no wire/DTO change) — slice-local is an internal optimization, not a protocol change.
- The old build_podcast_update call is removed from the per-domain (push) path; only the pull path and tests still call it.

## Open Tail

- Per-domain revs still bump on any mutation within that domain; further granularity (e.g. per-podcast revs) could reduce serialization further for large libraries.

## Evidence

- transcript lines 30-57
- transcript lines 134-154
- transcript lines 161-170
- transcript lines 7905-8054

