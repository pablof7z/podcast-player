---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-tombstones
  - last-emitted-advance
  - projection-contract
supersedes:
  - 2026-06-12-3-domain-sub-projections-via-per-domain
related_claims: []
source_lines:
  - 4334-4401
  - 4507-4528
captured_at: 2026-06-12T14:21:59Z
---

# Episode: Kernel tombstone contract for empty domain states

## Prior State

When a domain went empty (user signs out, clears downloads, unsubscribes from all podcasts), the domain builder returned `None` without advancing `last_emitted` or emitting any frame. This meant shells could never learn that a domain had become empty, and the empty domain's builder would re-run `build_podcast_update` (full snapshot build + store lock) on every tick forever.

## Trigger

Found during cycle-4 planning investigation of `snapshot_domain_projections.rs`: the `?` early-return on empty domains left `last_emitted` behind, creating both a semantic gap (shells can't learn 'empty') and a perf gap (full rebuild every tick for empty domains).

## Decision

Emit tombstone frames (`{"rev":N,"library":null}`, `{"rev":N,"downloads":null}`, `{"rev":N,"active_account":null}`, `{"rev":N,"widget":null}`) and always advance `last_emitted`. The `?` early-return was replaced with `.unwrap_or_else(|| tombstone(rev))` pattern.

## Consequences

- Shells can now correctly clear domain state when the server signals 'empty' (sign out, clear downloads, unsubscribe all)
- Empty domains no longer trigger perpetual full `build_podcast_update` on every tick
- Both shell consumers must handle `null` tombstone values (decode `decodeIfPresent` / `@SerialName` nullable fields → nil, merge clears the slice)
- Playback, settings, and misc domains always emit a payload (never empty), so no tombstone needed there

## Open Tail

*(none)*

## Evidence

- transcript lines 4334-4401
- transcript lines 4507-4528

