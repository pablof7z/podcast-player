---
type: episode-card
date: 2026-05-28
session: 1a2f2460-74e7-4309-9dcc-99d19936c123
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1a2f2460-74e7-4309-9dcc-99d19936c123.jsonl
salience: architecture
status: active
subjects:
  - podcast-tui
  - nmp-architecture
  - separation-of-concerns
supersedes: []
related_claims: []
source_lines:
  - 1904-1904
  - 2469-2469
captured_at: 2026-06-12T12:51:43Z
---

# Episode: TUI architectural doctrine: thin NMP shell, zero business logic

## Prior State

No explicit doctrine existed for what logic the TUI should own vs. the kernel

## Trigger

Building the TUI required deciding where subscribe, search, playback, download, and inbox logic should live

## Decision

TUI is a pure NMP shell — it dispatches actions and renders snapshots with zero business logic duplication; all subscription, playback state, search parsing, queue management, and download tracking remain in nmp-app-podcast

## Consequences

- Any feature already handled by the kernel is exposed by dispatching the right action string, not reimplemented
- TUI state is entirely derived from the kernel snapshot — no local authoritative state beyond UI cursor positions
- New features (subscribe-from-search, inbox, downloads) are added by wiring dispatch calls, not implementing logic

## Open Tail

*(none)*

## Evidence

- transcript lines 1904-1904
- transcript lines 2469-2469

