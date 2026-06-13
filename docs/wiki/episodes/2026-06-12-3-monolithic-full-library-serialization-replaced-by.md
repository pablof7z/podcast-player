---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-sub-projections
  - domain-revs
  - typed-sidecar
  - nmp-v0.5
supersedes:
  - 2026-06-12-1-snapshot-perf-root-cause-rev-bumps
related_claims: []
source_lines:
  - 3810-3828
  - 4204-4254
captured_at: 2026-06-12T13:02:10Z
---

# Episode: Monolithic full-library serialization replaced by per-domain typed sidecars

## Prior State

A single global AtomicU64 rev controlled all snapshot emission — any state change (playback tick, download progress, settings toggle) bumped the same rev, causing full-library re-serialization. The per-domain serialization functions already existed (snapshot_library.rs, snapshot_queue.rs, etc.) but fed into a single monolithic PodcastUpdate envelope

## Trigger

The performance root cause (57% CPU in full-library serialization) combined with the discovery that register_typed_snapshot_projection supports Option-gating (returning None omits the key from the frame entirely) — enabling per-domain delta frames without nmp-core changes

## Decision

Per-domain typed sidecars with per-domain revs: each domain (podcast.library, podcast.playback, podcast.downloads, podcast.inbox, podcast.settings, podcast.identity, podcast.widget, podcast.misc) has its own atomic rev. Unchanged domains return None from their typed-projection closure (omitted from frame). DomainRevs struct maps Domain → counter. Infra::bump advances both the domain counter and the global rev (global preserved for pull-path compatibility). Mutation sites tagged with domain scope via Infra::with_domain

## Consequences

- A playback position tick emits ~1 KB (playback sidecar only) instead of MBs (full library) — the 10x scale fix
- Global rev still drives the pull path unchanged — golden bytes byte-identical, no shell behavior change yet
- The end-to-end perf win requires Swift + Android consumers to migrate from full-library pull to per-domain frames (tracked follow-up)
- Domain assignment: PlaybackState→Playback, CategoriesState→Library, everything else→Misc (default); inbox folded into library payload

## Open Tail

- Shell consumers (Swift/Android) must migrate to per-domain frames to realize the end-to-end perf win

## Evidence

- transcript lines 3810-3828
- transcript lines 4204-4254

