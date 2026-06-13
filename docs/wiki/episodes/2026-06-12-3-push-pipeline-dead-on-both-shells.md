---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: superseded
subjects:
  - push-reactivity
  - ios-bridge
  - android-snapshot
  - frame-decode
supersedes: []
related_claims: []
source_lines:
  - 4341-4345
captured_at: 2026-06-12T13:58:37Z
---

# Episode: Push pipeline dead on both shells — not just perf but correctness

## Prior State

Push frames were assumed to deliver reactive updates to iOS and Android shells, supplementing the pull path

## Trigger

Cycle-4 planner investigation found: (a) iOS `KernelBridge.decode(pointer:)` still requires `v.projections["podcast.snapshot"]` which no longer exists → every push frame fails decode with 'snapshot frame missing podcast.snapshot projection'; (b) Android `SnapshotCodec.decodeEnvelope` decodes the slim `v` (rev/running/schema_version only) as a full `PodcastSnapshot` → every kernel emit clobbers the UI to an empty library state

## Decision

Per-domain push consumption is a correctness-critical item (not just perf): cycle-4 prioritized iOS per-domain sidecar consumption (Item A) and Android frame-clobber fix (Item B) alongside the kernel tombstone fix

## Consequences

- iOS has been 100% pull-driven since NMP v0.3.0 — background rev bumps only surface when an audio report or user dispatch happens to probe
- Android has an active correctness bug (UI clobbers to empty on kernel emits), masked only by infrequent emits while idle
- Both shells must be migrated to consume `podcast.*` sidecar projections

## Open Tail

- iOS per-domain consumption in progress (cycle-4 Item A)
- Android per-domain consumption deferred until kernel tombstone + Android CI land

## Evidence

- transcript lines 4341-4345

