---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-projections
  - snapshot-transport
  - kernel-architecture
supersedes:
  - 2026-06-12-2-generic-push-projection-is-vestigial-typed
related_claims: []
source_lines:
  - 161-161
  - 4173-4191
  - 4213-4232
  - 4234-4254
captured_at: 2026-06-12T13:58:37Z
---

# Episode: Per-domain typed sidecars adopted — omit unchanged domains per tick

## Prior State

Every actor tick re-serialized the entire podcast library (all podcasts × all episodes) into a single `PodcastUpdate` JSON envelope, regardless of which domain changed

## Trigger

Profiling showed 57% CPU in full-library JSON serialization; the existing rev-gated cache was defeated because `rev` bumped on nearly every tick (comments_handler, feed_fetch, knowledge, agent_note_handler, etc. all do `rev.fetch_add`)

## Decision

Adopt per-domain `DomainRevs` counters + typed projection sidecars. Each domain (Playback, Library, Downloads, Settings, Identity, Widget, Misc) has its own rev; the Tier-3 encoder omits sidecars whose domain rev hasn't advanced. `Infra::bump` always advances both the domain counter AND the global rev (safety: pull path gated on global rev is unaffected)

## Consequences

- A playback tick ships ~1KB sidecar instead of multi-MB full library
- Global rev still drives the unchanged pull path — no behavior change until shells consume sidecars
- bump_domain must be wired at every real mutation site (caught dormant scaffolding in review — #399 had only test bumps, #400 completed wiring)
- Shell consumption (Swift/Android) is the tracked follow-up to realize end-to-end perf win

## Open Tail

- Swift + Android consumers must be built to realize the 10x payload reduction

## Evidence

- transcript lines 161-161
- transcript lines 4173-4191
- transcript lines 4213-4232
- transcript lines 4234-4254

