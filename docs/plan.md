# Plan

This is the canonical project plan. Detailed implementation plans live under
`docs/plan/` and are linked from this file.

## Current Focus

| Work | State | Source |
|---|---|---|
| NMP feature parity — active PR stack. | **In progress** | `docs/plan/nmp-feature-parity.md` |
| Pod0 app rename. | In progress | `docs/BACKLOG.md` |
| Migrate owned podcast Nostr publishing/discovery from NIP-74 to NIP-F4. | In progress | `docs/plan/pod0-nostr-publishing.md` |

## Planning Files

- `docs/plan.md` - overarching plan and milestone status.
- `docs/BACKLOG.md` - tactical queue and follow-ups.
- `WIP.md` - active branches/worktrees only.
- `docs/plan/` - detailed implementation plans linked from this file.
  - `docs/plan/nmp-feature-parity.md` — full NMP feature-parity plan: 74 features, PR sequence, guiding principles, exit criteria.
  - `docs/plan/pod0-nostr-publishing.md` — NIP-F4 podcast publishing plan.

## Pod0 / NIP-F4 Milestones

| Milestone | Exit Criteria | Status |
|---|---|---|
| Pod0 protocol setup | `AGENTS.md`, `WIP.md`, `docs/plan.md`, and `docs/BACKLOG.md` define the NMP-style workflow. | Done |
| Pod0 app rename | User-facing app name reflects Pod0; stable identifiers unchanged. | In progress |
| NIP-F4 publishing | Publishes kind `10154`/`54`/`10064` with per-podcast keys. | In progress |
| NIP-F4 discovery | Discovery reads kind `10154`/`54`. | In progress |
