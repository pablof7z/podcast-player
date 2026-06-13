---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: active
subjects:
  - inbox-triage
  - d8-trigger
  - subscribe-triage
supersedes: []
related_claims: []
source_lines:
  - 5696-5757
  - 5765-5790
captured_at: 2026-06-12T22:05:45Z
---

# Episode: Inbox triage triggers immediately on async subscribe (D8 re-homing)

## Prior State

Freshly-subscribed and OPML-imported episodes did not triage immediately — the inbox triage trigger was not connected to the subscribe result path, creating a gap where new episodes sat unprocessed until a separate trigger fired.

## Trigger

D8 trigger re-homing directive from #383: freshly-subscribed episodes should triage immediately.

## Decision

Added `self.inbox.maybe_enqueue_triage()` to `apply_subscribe_result` (in `feed_fetch.rs`), gated identically to the adjacent `auto_categorize`/`auto_refresh_picks` (on `snapshot_signal.is_some()`). `InboxState` wrapped in `Arc<InboxState>` for cross-handler sharing.

## Consequences

- Newly subscribed/OPML-imported episodes triage immediately instead of waiting for a separate trigger
- Arc wrapping of InboxState enables shared mutable access across the coordinator and snapshot projection
- Golden snapshot byte-identical (3789 bytes) — this is a trigger re-homing, not a projection change

## Open Tail

*(none)*

## Evidence

- transcript lines 5696-5757
- transcript lines 5765-5790

