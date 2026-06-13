---
type: episode-card
date: 2026-05-28
session: 1a2f2460-74e7-4309-9dcc-99d19936c123
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1a2f2460-74e7-4309-9dcc-99d19936c123.jsonl
salience: root-cause
status: active
subjects:
  - podcast-tui
  - capability-callback
  - http-namespace
supersedes: []
related_claims: []
source_lines:
  - 1839-1904
captured_at: 2026-06-12T12:51:43Z
---

# Episode: HTTP capability handler required for iTunes search

## Prior State

TUI runtime only installed an audio capability callback; nmp.http.capability requests from iTunes search hit a stub 'unexpected namespace' error, so the kernel never wrote search results to the snapshot

## Trigger

Search always returned empty because the kernel's HTTP capability requests had no handler

## Decision

Added reqwest::blocking HTTP executor to the capability callback, matching the headless binary's approach

## Consequences

- iTunes search works end-to-end from the TUI
- TUI must now include reqwest as a dependency and handle HTTP capability dispatch in its runtime loop

## Open Tail

*(none)*

## Evidence

- transcript lines 1839-1904

