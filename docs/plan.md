# Plan

This is the canonical project plan. Detailed implementation plans live under
`docs/plan/` and are linked from this file. Historical plans under `Plans/`
are reference material, not the active planning surface.

## Current Focus

| Work | State | Source |
|---|---|---|
| Rename the working app identity to Pod0 while preserving App Store, bundle ID, App Group, and stored-data continuity. | In progress | `docs/BACKLOG.md` |
| Migrate owned podcast Nostr publishing and discovery from NIP-74 to NIP-F4. | In progress | `docs/plan/pod0-nostr-publishing.md` |
| Run all implementation through agent-owned worktrees with PRs and live `WIP.md` tracking. | Active protocol | `AGENTS.md` |

## Planning Files

- `docs/plan.md` - overarching plan and milestone status.
- `docs/BACKLOG.md` - tactical queue and follow-ups.
- `WIP.md` - active branches/worktrees only.
- `docs/plan/` - detailed implementation plans linked from this file.

## Milestones

| Milestone | Exit Criteria | Status |
|---|---|---|
| Pod0 protocol setup | `AGENTS.md`, `WIP.md`, `docs/plan.md`, and `docs/BACKLOG.md` define the NMP-style workflow for this repo. | In progress |
| Pod0 app rename | User-facing app name, generated project identity, shortcuts, widgets, tests, and changelog reflect Pod0; stable identifiers remain unchanged. | Not started |
| NIP-F4 publishing | Public podcast creation/update publishes kind `10154` show events, kind `54` episode events, and kind `10064` author claims with per-podcast keys. | Not started |
| NIP-F4 discovery | Nostr discovery reads kind `10154` shows and kind `54` episodes keyed by podcast pubkey. | Not started |
| Verification and PR | Focused tests/builds pass, `git diff --check` is clean, and a ready-for-review PR is opened. | Not started |
