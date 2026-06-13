---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - domain-sub-projections
  - typed-sidecar
  - per-domain-rev
supersedes:
  - 2026-06-12-3-kernel-tombstone-contract-for-empty-domain
  - 2026-06-12-3-per-domain-delta-transport-replacing-monolithic
related_claims: []
source_lines:
  - 3810-3828
  - 4204-4232
captured_at: 2026-06-12T13:47:03Z
---

# Episode: Per-domain typed sidecars replace monolithic podcast snapshot

## Prior State

A single global rev drives a monolithic PodcastUpdate — any substate change (playback position tick, download progress) triggers full-library re-serialization and a multi-MB payload.

## Trigger

Profiling showed 57% CPU in serialization; the rev-gated cache is defeated; the generic push projection is dead. The typed-sidecar seam (register_typed_snapshot_projection) already exists in v0.5.0 with Option-gating (None = omit from frame).

## Decision

Per-domain DomainRevs + typed sidecars: each substate has its own domain counter; Infra::bump advances both domain + global rev; unchanged domains return None (omitted from frame). Domains: podcast.library, podcast.playback, podcast.downloads, podcast.inbox, podcast.settings, podcast.identity, podcast.widget, podcast.misc.

## Consequences

- A playback position tick emits only the ~1KB playback sidecar, not a multi-MB library pull
- Global rev is always bumped alongside domain rev — the existing pull path (what shells use today) is completely unaffected
- The per-domain serialization functions already existed (snapshot_library.rs, snapshot_queue.rs, etc.) — re-aimed at per-domain envelopes
- End-to-end perf win requires Swift/Android consumers to read per-domain frames; until then the infra is dormant-by-design but correct

## Open Tail

- Swift KernelModel must apply per-domain payloads instead of pullPodcastSnapshotIfChanged for full realization
- Android PodcastSnapshot.kt needs the same migration

## Evidence

- transcript lines 3810-3828
- transcript lines 4204-4232

