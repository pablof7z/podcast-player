---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-sub-projections
  - per-domain-rev
  - typed-sidecar
supersedes:
  - 2026-06-12-3-architecture-pivot-domain-sub-projections-via
related_claims: []
source_lines:
  - 3811-3828
captured_at: 2026-06-12T11:45:46Z
---

# Episode: Domain sub-projections via per-domain typed sidecars with Option-gating

## Prior State

The plan was to split the monolithic `podcast.snapshot` into per-domain keys using `register_snapshot_projection_gated` — the same generic JSON projection mechanism that was already vestigial.

## Trigger

Verified finding that generic projections are discarded by the Tier-3 encoder, combined with the perf root cause (full-library re-serialization on every tick).

## Decision

Use `NmpApp::register_typed_snapshot_projection(key, || Option<TypedProjectionData>)` with per-domain revs. Each substate gets its own `DomainRev`; unchanged domains return `None` (omitted from frame entirely). Domain set: `podcast.library`, `podcast.playback`, `podcast.downloads`, `podcast.inbox`, `podcast.settings`, `podcast.identity`, `podcast.widget`, `podcast.misc`. Global rev preserved for pull-path compatibility; domain revs drive push-sidecar emission.

## Consequences

- A playback position tick ships ~1 KB instead of multi-MB full-library JSON
- Per-domain serializers already exist (`snapshot_library.rs`, `snapshot_queue.rs`, etc.) — re-aimed at per-domain envelopes
- iOS/Android consumers apply per-domain payloads from frame, with pull as cold-start hydration fallback (staged cutover, no flag-day)
- Existing `nmp_app_podcast_decode_update_frame` extended to decode all `podcast.*` sidecars into `v.projections[key]`

## Open Tail

- PR-2 (Rust kernel producers) is the long pole and must not be parallelized with anything touching register.rs/snapshot*.rs/state/

## Evidence

- transcript lines 3811-3828

