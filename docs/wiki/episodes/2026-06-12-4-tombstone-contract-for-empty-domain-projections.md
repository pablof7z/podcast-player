---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - tombstone
  - domain-projections
  - kernel-contract
supersedes:
  - 2026-06-12-4-kernel-tombstone-on-empty-contract-for
related_claims: []
source_lines:
  - 4438-4439
  - 4507-4529
captured_at: 2026-06-12T14:47:13Z
---

# Episode: Tombstone contract for empty domain projections

## Prior State

When a domain's rev advanced but its payload was empty (e.g., user unsubscribed from all podcasts), the `?` early-return left `last_emitted` behind, causing the empty domain to rebuild on every tick. Shells had no way to learn 'domain is now cleared.'

## Trigger

Per-domain sidecars need to signal 'cleared' to shell consumers — a domain going from populated to empty is a real state change.

## Decision

Replace the `?` early-return with `unwrap_or_else(|| tombstone(rev))` so `last_emitted` always advances. Tombstone shapes are `{"rev":N,"library":null}`, `{"rev":N,"downloads":null}`, etc. Shells decode tombstones via `decodeIfPresent` and clear the corresponding slice (library → `[]`, downloads → nil, identity → activeAccount = nil).

## Consequences

- Empty domains now correctly signal 'cleared' to shells
- Eliminates the CPU waste of rebuilding empty projections every tick
- Both iOS and Android handle tombstones: iOS maps null → empty slice/nil, Android maps null → emptyList()/nil via `coerceInputValues = true`

## Open Tail

*(none)*

## Evidence

- transcript lines 4438-4439
- transcript lines 4507-4529

