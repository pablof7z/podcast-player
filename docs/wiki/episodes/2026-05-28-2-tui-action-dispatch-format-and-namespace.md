---
type: episode-card
date: 2026-05-28
session: f1804b3d-52ea-4a3f-bbf2-608cef7c7468
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f1804b3d-52ea-4a3f-bbf2-608cef7c7468.jsonl
salience: product
status: active
subjects:
  - podcast-tui-action-dispatch
  - kernel-action-protocol
supersedes: []
related_claims: []
source_lines:
  - 2497-2499
captured_at: 2026-06-12T12:52:36Z
---

# Episode: TUI action dispatch format and namespace corrected

## Prior State

Every kernel action from the TUI used the wrong JSON variant shape ({"VariantName":{...}}) and wrong namespaces, so no TUI action (subscribe, play, search, etc.) ever actually reached the kernel processing pipeline.

## Trigger

Bug investigation into subscribe failure revealed that runtime.rs dispatched actions with incorrect serialization and namespace routing compared to the kernel's expected format.

## Decision

All action dispatches now use the kernel's contract: {"op":"snake_case",...} with correct namespaces (podcast, podcast.player, podcast.queue, podcast.inbox).

## Consequences

- Subscribe-by-URL now correctly triggers the kernel's PodcastActionModule
- All other TUI actions (play, pause, seek, queue management) now reach their intended handlers
- The serde tag+rename_all convention on PodcastAction must be the source of truth for action wire format

## Open Tail

*(none)*

## Evidence

- transcript lines 2497-2499

