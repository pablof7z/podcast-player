---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: superseded
subjects:
  - push-pipeline
  - ios-bridge
  - android-snapshot
  - reactivity
supersedes:
  - 2026-06-12-2-push-path-was-dead-on-both
related_claims: []
source_lines:
  - 4340-4346
captured_at: 2026-06-12T14:08:15Z
---

# Episode: Push pipeline dead on both shells — correctness bug, not just perf

## Prior State

Push frames were assumed to work (just slowly). iOS and Android were believed to receive kernel updates reactively.

## Trigger

Cycle-4 planner discovered: (1) iOS KernelBridge.decode still requires v.projections["podcast.snapshot"] which the v0.3.0 typed-first encoder stopped producing → every push frame fails decode silently. (2) Android decodeEnvelope decodes the slim v (rev/running/schema_version only) as a full PodcastSnapshot → empty library → every kernel emit clobbers UI to empty state.

## Decision

Per-domain shell consumption is prioritized as a correctness fix, not just a perf optimization. iOS must consume podcast.* sidecars (not the deleted podcast.snapshot). Android must decode domain sidecars instead of the slim v as a full snapshot.

## Consequences

- iOS is 100% pull-driven today — background rev bumps only surface when audio reports or user dispatches happen to probe
- Android has an active UI-clobbering bug (masked by infrequent idle emits)
- The per-domain consumption work (Items A and B) restores real push reactivity on both platforms

## Open Tail

- iOS per-domain consumption (Item A) in flight
- Android consumption (Item B) deferred until C+E land

## Evidence

- transcript lines 4340-4346

