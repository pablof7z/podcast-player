---
type: episode-card
date: 2026-05-28
session: 1a2f2460-74e7-4309-9dcc-99d19936c123
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1a2f2460-74e7-4309-9dcc-99d19936c123.jsonl
salience: product
status: superseded
subjects:
  - podcast-tui
  - search
  - subscribe
supersedes: []
related_claims: []
source_lines:
  - 1933-1933
  - 2459-2461
captured_at: 2026-06-12T12:51:43Z
---

# Episode: Subscribe from search: view-only to actionable

## Prior State

Search results were view-only — user could see podcasts but could not subscribe

## Trigger

User directive: 'add subscribe from search in a background agent'

## Decision

Pressing Enter or 's' on a search result dispatches podcast.subscribe with the result's feed_url; the NMP kernel actor thread handles RSS fetch, parse, and store update asynchronously; the TUI sees the new podcast appear in the Library tab on the next snapshot tick

## Consequences

- Users can subscribe directly from iTunes search results in the TUI
- Subscription is asynchronous — no UI blocking, podcast appears on next poll
- Follows the NMP dispatch-and-observe pattern rather than direct implementation

## Open Tail

*(none)*

## Evidence

- transcript lines 1933-1933
- transcript lines 2459-2461

