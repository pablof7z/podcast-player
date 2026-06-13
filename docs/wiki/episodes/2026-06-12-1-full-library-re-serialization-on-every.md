---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - snapshot-perf
  - build-snapshot-payload
  - serde-json-hotpath
supersedes: []
related_claims: []
source_lines:
  - 30-57
captured_at: 2026-06-12T13:02:10Z
---

# Episode: Full-library re-serialization on every kernel tick is the CPU/memory root cause

## Prior State

The podcast app had unexplained CPU pegging and a 14.6 GB physical footprint; the code's own comment claimed a 'rev-gated snapshot-string cache' should prevent re-serialization

## Trigger

Process sampling (21680) showed 57% of samples in build_snapshot_payload → serde_json::to_string, and the rev cache is defeated because rev bumps on essentially every actor tick (multiple handlers call fetch_add)

## Decision

The root cause is structural: every command dispatch triggers emit_now → make_update → build_snapshot_payload, which re-serializes the entire library (all podcasts × all episodes) on the actor thread. The rev cache is correct but useless under high-churn rev

## Consequences

- Any single-state mutation (playback position tick, download progress) triggers full-library JSON serialization
- The string-escaping leaf (format_escaped_str) is a symptom, not the cause — the fix must reduce what gets serialized per tick
- The 14.6 GB footprint likely comes from accumulated allocations from repeated full-library serializations

## Open Tail

- The specific fix (domain sub-projections) is a separate arc

## Evidence

- transcript lines 30-57

