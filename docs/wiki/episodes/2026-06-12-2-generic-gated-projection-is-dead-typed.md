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
  - typed-sidecars
  - nmp-v0.5
supersedes:
  - 2026-06-12-2-gated-podcast-snapshot-push-projection-is
related_claims: []
source_lines:
  - 3799-3828
  - 3868-3883
captured_at: 2026-06-12T12:10:51Z
---

# Episode: Generic gated projection is dead — typed sidecars are the v0.5.0 seam

## Prior State

The `register_snapshot_projection_gated("podcast.snapshot", …)` block in register.rs was the established mechanism for push-based snapshot delivery, and the prior cycle's optimization work (rev-gating) was built around it. Its own comment says it "rides the generic push frame."

## Trigger

The Fable planner discovered, and independent verification confirmed, that since NMP v0.3.0 (ADR-0044), the Tier-3 frame encoder encodes ONLY the typed envelope + typed-projection FlatBuffer sidecars and discards the `KernelSnapshot::projections` map entirely. All real consumers (iOS, Android, headless, TUI) use the pull symbol `nmp_app_podcast_snapshot`. The gated projection runs `serde_json::from_str` of multi-MB payloads on every rev change — output thrown away — and `Value::clone()` of cached multi-MB trees on unchanged ticks — also thrown away.

## Decision

Delete the dead `register_snapshot_projection_gated("podcast.snapshot")` block entirely (verified-safe, immediate CPU win). Replace with per-domain typed sidecars registered via `register_typed_snapshot_projection(key, || Option<TypedProjectionData>)`, where returning `None` omits unchanged domains from the frame entirely. No nmp-core change needed — the seam already exists in v0.5.0.

## Consequences

- The earlier rev-gated projection optimization was optimizing a path the encoder already discards — it must be deleted, not improved
- Per-domain typed sidecars with Option-gating produce true delta frames: a playback tick ships ~1KB instead of MBs
- The pull path (`nmp_app_podcast_snapshot`) remains the cold-start hydration mechanism; push delivers per-domain deltas
- This reframes the headline perf item from 'split the generic projection' to 'use the correct typed-sidecar seam'

## Open Tail

- PR-1: delete dead projection (immediate); PR-2: per-domain typed sidecars + revs (long pole); PR-3/4: Swift/Android consumers

## Evidence

- transcript lines 3799-3828
- transcript lines 3868-3883

