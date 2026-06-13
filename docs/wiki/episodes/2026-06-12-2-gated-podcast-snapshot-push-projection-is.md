---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - snapshot-projection
  - tier3-encoder
  - dead-code
supersedes:
  - 2026-06-12-2-gated-podcast-snapshot-projection-is-dead
related_claims: []
source_lines:
  - 3802-3867
captured_at: 2026-06-12T13:47:03Z
---

# Episode: Gated podcast.snapshot push projection is dead code in v0.5.0

## Prior State

The register_snapshot_projection_gated('podcast.snapshot') block was believed to be a useful optimization — its comment says Podcast state now rides the generic push frame, replacing the shell's 500ms poll.

## Trigger

Fable planner discovered (verified against nmp-core source) that since ADR-0044/v0.3.0, the Tier-3 encoder discards the generic KernelSnapshot::projections map — it encodes only the typed envelope + FlatBuffer sidecars. Every real consumer uses the pull symbol nmp_app_podcast_snapshot.

## Decision

Delete the dead projection registration entirely (PR #396). The v0.5.0-native seam is register_typed_snapshot_projection with Option-gating.

## Consequences

- Immediate actor-thread CPU win: no more multi-MB from_str on rev change or Value::clone on unchanged ticks
- The 'generic push frame' comment in register.rs was stale — the push path for podcast data never reached any shell
- Future optimizations must use typed sidecars, not the generic projections map

## Open Tail

*(none)*

## Evidence

- transcript lines 3802-3867

