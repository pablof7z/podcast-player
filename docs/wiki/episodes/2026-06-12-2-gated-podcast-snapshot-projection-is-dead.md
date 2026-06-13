---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - podcast-snapshot-projection
  - register-snapshot-projection-gated
  - nmp-encoder
supersedes:
  - 2026-06-12-2-dead-projection-discovery-gated-podcast-snapshot
related_claims: []
source_lines:
  - 3798-3883
  - 4187-4196
captured_at: 2026-06-12T13:02:10Z
---

# Episode: Gated podcast.snapshot projection is dead — deleted after typed-first encoder evolution

## Prior State

register_snapshot_projection_gated("podcast.snapshot") was created as an optimization (replacing a 500ms poll, described as a 'D8 violation / reborn deprecated chirp_snapshot pattern') — its own comment said it 'rides the generic push frame'

## Trigger

Fable planner discovered, and independent verification confirmed, that since ADR-0044 / NMP v0.3.0, encode_snapshot_with_envelope encodes ONLY the typed Tier-3 envelope + typed_projections FlatBuffer sidecar and discards the generic KernelSnapshot::projections map. Every real consumer (iOS, Android, headless, TUI) uses the pull symbol nmp_app_podcast_snapshot, not the pushed projection

## Decision

The gated projection registration is pure actor-thread waste: multi-MB from_str on every rev-changed tick + multi-MB Value::clone on every unchanged tick, with output discarded by the encoder. Deleted in PR #396

## Consequences

- Immediate actor-thread CPU win (removed multi-MB JSON round-trip per tick)
- The correct v0.5.0-native seam is register_typed_snapshot_projection with Option-gating, not the generic JSON projection
- The comment claiming the projection 'rides the generic push frame' was stale since v0.3.0

## Open Tail

*(none)*

## Evidence

- transcript lines 3798-3883
- transcript lines 4187-4196

