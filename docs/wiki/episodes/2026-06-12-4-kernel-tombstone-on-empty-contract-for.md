---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - domain-projections
  - tombstone
  - last-emitted
supersedes:
  - 2026-06-12-4-tombstone-on-empty-kernel-contract-empty
related_claims: []
source_lines:
  - 4507-4530
captured_at: 2026-06-12T14:08:15Z
---

# Episode: Kernel tombstone-on-empty contract for domain projections

## Prior State

When a domain projection builder returned None (empty state — library/downloads/identity/widget), the ? early-return left last_emitted unchanged and no frame was emitted. Shells could never learn 'downloads cleared / signed out / unsubscribed-all', and the empty domain re-ran build_podcast_update (full snapshot build, store lock) every tick forever.

## Trigger

Cycle-4 planner found the contract gap in snapshot_domain_projections.rs — a domain that goes empty has no way to signal that state to consumers, and the kernel wastes CPU rebuilding it every tick.

## Decision

Replace ? early-return with .unwrap_or_else(|| tombstone(rev)) so last_emitted always advances. Emit {"rev":N,"<field>":null} tombstone shapes for the 4 nullable domains (library, downloads, identity, widget). Playback, settings, and misc always produce a payload (no tombstone needed).

## Consequences

- Shells can detect cleared/empty state via null tombstones
- Empty domains no longer re-run full builds every tick
- The kernel domain-projection contract is complete for shell consumption

## Open Tail

*(none)*

## Evidence

- transcript lines 4507-4530

