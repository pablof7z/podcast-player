---
type: episode-card
date: 2026-05-28
session: f1804b3d-52ea-4a3f-bbf2-608cef7c7468
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f1804b3d-52ea-4a3f-bbf2-608cef7c7468.jsonl
salience: product
status: active
subjects:
  - podcast-tui-inbox-tab
supersedes: []
related_claims: []
source_lines:
  - 1997-2028
  - 2265-2267
captured_at: 2026-06-12T12:52:36Z
---

# Episode: Inbox tab added to TUI navigation

## Prior State

TUI had four tabs: Library, Queue, Search, Settings. No Inbox surface existed despite PodcastUpdate carrying inbox data from the kernel.

## Trigger

During the snapshot refactor, PodcastUpdate.inbox data became natively available; the Tab enum was extended to include Inbox.

## Decision

Added Tab::Inbox to the navigation cycle (Library→Queue→Inbox→Search→Settings) with corresponding handle_inbox_keys and ui::inbox render module.

## Consequences

- TUI now surfaces AI-triaged inbox items (episode_id, priority_score, priority_reason, ai_categories)
- Tab exhaustiveness requires all match arms in input.rs, layout.rs, and app.rs to handle Inbox
- InboxRow struct mirrors InboxItem from nmp-app-podcast projections

## Open Tail

- Inbox tab UI rendering is stubbed (handle_inbox_keys is a no-op); full interaction not yet implemented

## Evidence

- transcript lines 1997-2028
- transcript lines 2265-2267

