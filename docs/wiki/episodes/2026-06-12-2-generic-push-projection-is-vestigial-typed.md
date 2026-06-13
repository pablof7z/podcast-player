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
  - nmp-v0.5.0
supersedes:
  - 2026-06-12-2-generic-gated-projection-is-dead-typed
related_claims: []
source_lines:
  - 3798-3860
  - 3862-3883
captured_at: 2026-06-12T11:45:46Z
---

# Episode: Generic push projection is vestigial — typed sidecars are the only path to the wire

## Prior State

The `register_snapshot_projection_gated("podcast.snapshot")` block in register.rs was believed to be a meaningful optimization — its own comment reads "Podcast state now rides the generic push frame under projections[\"podcast.snapshot\"]" — and the prior plan was to split it into per-domain keys via the same generic registration.

## Trigger

Fable planner discovered, and session verified independently: since NMP v0.3.0 (ADR-0044), the Tier-3 encoder (`encode_snapshot_with_envelope`) encodes ONLY the typed envelope + typed-projection FlatBuffer sidecars; the `KernelSnapshot::projections` map is built every emit and then discarded by the encoder. Every real consumer (iOS, Android, TUI) uses the pull symbol `nmp_app_podcast_snapshot`, not the registered projection.

## Decision

The gated `"podcast.snapshot"` registration is pure actor-thread waste (multi-MB `from_str` on every rev change with output discarded; multi-MB `Value::clone` on unchanged ticks, also discarded). Delete it immediately. Use `register_typed_snapshot_projection` with per-domain `Option`-gating for the real fix.

## Consequences

- PR-1 (delete dead projection) is zero-risk with immediate CPU win
- The entire per-domain sub-projection architecture must target typed sidecars, not generic projections
- Per-domain revs with `None` return on unchanged domains means omitted from the frame entirely — true delta frames, not just stale-gated clones
- No nmp-core change needed — the typed sidecar seam already exists in v0.5.0

## Open Tail

- PR-2 (per-domain typed sidecar producers) is the long-pole; PR-3 (Swift) and PR-4 (Android) follow after

## Evidence

- transcript lines 3798-3860
- transcript lines 3862-3883

