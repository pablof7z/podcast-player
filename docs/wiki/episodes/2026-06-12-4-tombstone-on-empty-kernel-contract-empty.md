---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-projections
  - tombstone-contract
  - snapshot-transport
supersedes:
  - 2026-06-12-4-tombstone-contract-for-empty-domain-projections
related_claims: []
source_lines:
  - 4334-4401
  - 4507-4528
captured_at: 2026-06-12T13:58:37Z
---

# Episode: Tombstone-on-empty kernel contract — empty domains must signal clearance

## Prior State

When a domain projection builder returned `None` (empty state — e.g., downloads cleared, signed out), the `?` early-return left `last_emitted` behind without advancing it or emitting a tombstone. Consequences: (a) shells consuming sidecars could never learn 'downloads cleared / signed out / unsubscribed-all'; (b) an empty domain re-ran `build_podcast_update` (full snapshot build + store lock) every tick forever

## Trigger

Code audit during cycle-4 planning found the `?` early-return in `snapshot_domain_projections.rs` — `last_emitted` never advanced on None

## Decision

Replace `?` early-return with `.unwrap_or_else(|| tombstone(rev))` so `last_emitted` always advances. Tombstones are `{"rev":N,"<field>":null}` shapes for library/downloads/identity/widget (playback/settings/misc always emit a payload)

## Consequences

- Shells can now receive 'cleared' signals for domains
- Empty domains no longer re-run the full build every tick
- 4 tests prove tombstone-then-idle behavior

## Open Tail

*(none)*

## Evidence

- transcript lines 4334-4401
- transcript lines 4507-4528

