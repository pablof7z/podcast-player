---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - snapshot-payload
  - domain-rev
  - projection-performance
supersedes:
  - 2026-06-13-1-1hz-whole-library-serialization-replaced-by
related_claims: []
source_lines:
  - 30-57
  - 134-154
  - 7950-8055
captured_at: 2026-06-13T03:58:09Z
---

# Episode: Kill 1Hz whole-library snapshot rebuild with slice-local domain payloads

## Prior State

Every command dispatch triggered emit_now → build_snapshot_payload, which re-serialized the entire podcast library (all podcasts × all episodes) to JSON on the actor thread. A rev-gated cache existed but was defeated because rev was bumped by numerous low-level mutators (comments, feed_fetch, knowledge, agent_notes, picks) on essentially every tick, causing 57% CPU in serde_json::to_string and a 14.6 GB physical footprint from accumulated allocations.

## Trigger

CPU profile (sample 21680) showed 1,633/2,856 samples (~57%) in build_snapshot_payload → serde_json::to_string, with format_escaped_str as the leaf bottleneck. Investigation of the rev-gated cache showed it was correct but useless because rev bumped every tick.

## Decision

Replace whole-library rebuild-on-every-tick with slice-local domain payload builders: each domain (library, queue, social, etc.) builds only its own sub-payload, gated on its own per-domain rev. Queue rows use the shared episode_summary helper (byte-identical to the library path by construction) instead of hardcoded empty fields for description, chapters, ai_categories, ad_segments, triage_*, transcript_status.

## Consequences

- 57% CPU hot path eliminated; 1Hz whole-library JSON serialization replaced by per-domain re-projection only when that domain's state actually changes
- Queue rows now carry full content (description, chapters, transcript) instead of empty stubs — byte-identity guaranteed by shared helper + regression test
- Per-domain revs require the real-bump rule: domain_revs.X must be bumped at the actual mutation site (infra.bump()), not via manual fetch_add in tests (lesson from #423 regression)
- Latent question: agent-chat/voice/clips/comments mutators use signal.bump() (global rev only), not domain revs, so their tokens produce frames where every domain closure returns None — the pull path remains the hydration fallback

## Open Tail

- Whether agent-chat/voice deltas need their own domain rev to ride the push frame without a full re-pull

## Evidence

- transcript lines 30-57
- transcript lines 134-154
- transcript lines 7950-8055

