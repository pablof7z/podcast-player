---
type: episode-card
date: 2026-06-09
session: 04b5f843-fdbe-4aa1-ae41-6770eac82957
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/04b5f843-fdbe-4aa1-ae41-6770eac82957.jsonl
salience: architecture
status: active
subjects:
  - kernel-bridge
  - snapshot-schema
  - fail-closed
supersedes: []
related_claims: []
source_lines:
  - 1780-1975
captured_at: 2026-06-12T13:40:38Z
---

# Episode: Snapshot schema-version fail-closed gate

## Prior State

No schema-version guard existed; a stale-shaped snapshot would decode against the current model fields, silently producing corrupt UI without any signal

## Trigger

Issue #356 — finding that schema mismatches could corrupt the library view invisibly with no diagnostic trail

## Decision

Fail closed: reject snapshots whose schema_version doesn't match KERNEL_SCHEMA_VERSION (currently 1); emit REJECTED faults on mismatch, rendering an empty library instead of corrupt data

## Consequences

- Future schema bumps will cause old builds to show an empty library with observable diagnostic faults instead of silently corrupt UI
- Migrations must increment KERNEL_SCHEMA_VERSION; old builds cannot silently render stale-shaped data
- Version mismatch is now a kernel invariant enforced at the Swift decode boundary

## Open Tail

*(none)*

## Evidence

- transcript lines 1780-1975

