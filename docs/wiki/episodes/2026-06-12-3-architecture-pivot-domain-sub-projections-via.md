---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-sub-projections
  - typed-sidecar
  - nmp-v0.5.0
  - per-domain-revs
supersedes:
  - 2026-06-12-2-per-domain-typed-sidecars-adopted-omit
related_claims: []
source_lines:
  - 3803-3827
  - 4173-4200
captured_at: 2026-06-12T12:24:35Z
---

# Episode: Architecture pivot: domain sub-projections via typed sidecars, not gated JSON projections

## Prior State

The plan was to split the monolithic podcast.snapshot into per-domain keys using the existing register_snapshot_projection_gated seam — same mechanism, just with finer-grained keys

## Trigger

Fable planner discovered and the assistant verified that the gated JSON projection seam is dead (output discarded); the v0.5.0-native seam register_typed_snapshot_projection already exists and supports Option-gating (returning None omits the key from the frame entirely) — strictly better than the JSON gate which still clones+ships unchanged keys

## Decision

Use register_typed_snapshot_projection with per-domain revs and Option-gating: each domain serializer targets a TypedProjectionData envelope; unchanged domain rev → return None (omitted from frame entirely); changed → JSON bytes in TypedProjectionData{schema_id, version}. Per-domain revs are app-local (no nmp-core change needed). The pull path stays for cold-start hydration

## Consequences

- Per-domain push deltas: a playback tick ships ~1KB instead of multi-MB full-library payload
- Zero upstream nmp-core changes required — all app-local
- Shell consumption (PR-3 Swift, PR-4 Android) is a staged cutover with pull fallback, never a flag-day
- PR #399 landed the infra/types/decode but was sent back because bump_domain was never wired at real mutation sites (dormant scaffolding)

## Open Tail

- Complete bump_domain wiring at real mutation sites in #399
- Swift consumption (PR-3) after kernel side lands
- Android consumption (PR-4) after Item 2 lands

## Evidence

- transcript lines 3803-3827
- transcript lines 4173-4200

