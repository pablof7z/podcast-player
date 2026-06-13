---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-perf
  - episode-summary
  - domain-projections
supersedes:
  - 2026-06-13-1-kill-1hz-whole-library-rebuild-with
related_claims: []
source_lines:
  - 1-57
  - 122-161
  - 8003-8098
captured_at: 2026-06-13T03:49:37Z
---

# Episode: 1Hz whole-library serialization replaced by slice-local domain payloads

## Prior State

Every command dispatch triggered emit_now → build_snapshot_payload, re-serializing the entire podcast library (all podcasts × all episodes) to JSON on the actor thread. The rev-gated snapshot cache was defeated because rev bumped on essentially every actor tick — 1,633/2,856 samples (~57%) were in serde_json::to_string, and physical footprint was 14.6 GB from accumulated allocations.

## Trigger

Profile of process 21680 showed 57% CPU time in build_snapshot_payload → serde_json::to_string, with the leaf bottleneck in format_escaped_str on huge payloads. Investigation revealed the rev-gated cache was correct but rev was bumping on every tick, making the cache ineffective.

## Decision

Replace whole-library serialization with slice-local domain payload builders. Queue rows now use a shared episode_summary helper (extracted from build_library_snapshot) that only resolves the queued episodes, not all episodes. Byte-identity between library and queue paths is guaranteed by construction via the shared helper, not by field-by-field copying.

## Consequences

- The 1Hz whole-library-rebuild perf drain is eliminated; queue path is slice-local (only queued episodes resolved)
- Hardcoded empty fields in the queue builder (description: None, chapters: Vec::new(), etc.) replaced by the shared helper, closing a data-regression gap caught in review
- New regression test (queue_row_byte_identical_to_full_snapshot_for_content_rich_episode) ensures both paths stay in sync
- No wire/DTO change — EpisodeSummary fields untouched, no codegen drift

## Open Tail

- A latent correctness question remains: whether push frames ever carry agent-chat/voice deltas if they never advance a domain rev (noted in BACKLOG)

## Evidence

- transcript lines 1-57
- transcript lines 122-161
- transcript lines 8003-8098

