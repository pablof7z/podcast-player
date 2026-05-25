# Backlog

This is the tactical queue for active work, follow-ups, and pending decisions.
Do not duplicate these items in `WIP.md`; `WIP.md` only records branches and
worktrees currently in flight.

## Active

- **P0 - Pod0 rename.** Rename the working app identity from Pod0's previous name where users or generated project surfaces see the app name. Preserve stable identifiers unless an explicit migration plan says otherwise: `io.f7z.podcast`, `io.f7z.podcast.widget`, `group.com.podcastr.app`, URL scheme/data identifiers, and existing Keychain/data continuity should not be changed as part of the display-name rename.
- **P0 - NIP-F4 owned podcast publishing.** Implement `docs/plan/pod0-nostr-publishing.md`: per-podcast keys, kind `10154` show events, kind `54` episode events, kind `10064` author claims, and deletion cleanup.
- **P0 - NIP-F4 discovery.** Update discovery parsing and episode fetches for kind `10154`/`54`, no `d` tags, and stable UUID derivation from `10154:<podcast-pubkey>`.
- **P1 - Planning cleanup.** Treat existing tracked files under `Plans/` as historical reference. Promote any active future work into `docs/plan.md`, `docs/BACKLOG.md`, or a linked `docs/plan/` detail file instead of adding new files under `Plans/`.

## Pending Decisions

- None currently. If a change would alter bundle IDs, App Group identifiers, URL schemes, persisted state keys, or relay/event compatibility beyond the active plan, add the decision here before implementation.

## Done

- 2026-05-25 - Moved the active Pod0/NIP-F4 implementation plan into `docs/plan/pod0-nostr-publishing.md` and added canonical planning files.
