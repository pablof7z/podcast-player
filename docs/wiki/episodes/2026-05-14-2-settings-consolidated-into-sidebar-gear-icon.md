---
type: episode-card
date: 2026-05-14
session: 1eb0c519-6723-489e-b777-71997fd7e216
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1eb0c519-6723-489e-b777-71997fd7e216.jsonl
salience: product
status: active
subjects:
  - settings-access
  - sidebar
  - toolbar
supersedes: []
related_claims: []
source_lines:
  - 1342-1344
captured_at: 2026-06-12T12:23:41Z
---

# Episode: Settings consolidated into sidebar, gear icon removed

## Prior State

Settings was accessible via a gear icon (⚙) in the top-right toolbar with a Cmd+, keyboard shortcut.

## Trigger

User said 'move settings inside the sidebar too' after Settings was already added as a sidebar nav button.

## Decision

Removed the gear icon ToolbarItem from `sharedToolbar()`. Settings is now exclusively accessible through the sidebar.

## Consequences

- Single entry point for Settings (sidebar only)
- Cmd+, keyboard shortcut for Settings no longer available
- Top-right toolbar now only contains the search magnifyingglass icon

## Open Tail

*(none)*

## Evidence

- transcript lines 1342-1344

