---
type: episode-card
date: 2026-05-28
session: 1a2f2460-74e7-4309-9dcc-99d19936c123
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1a2f2460-74e7-4309-9dcc-99d19936c123.jsonl
salience: architecture
status: active
subjects:
  - podcast-tui
  - nmp-kernel
  - flatbuffers
supersedes:
  - 2026-05-28-1-tui-state-sync-switched-from-push
related_claims: []
source_lines:
  - 2420-2435
captured_at: 2026-06-12T12:51:43Z
---

# Episode: FlatBuffer binary frames handled alongside JSON snapshots

## Prior State

apply_nmp_event assumed all payloads were JSON, causing parse errors on binary frames

## Trigger

NMP kernel sends FlatBuffer binary frames (empty or non-JSON) that crashed the JSON parser

## Decision

apply_nmp_event now silently ignores empty payloads, and attempts JSON parse only on non-empty payloads; state polling uses nmp_app_podcast_snapshot directly

## Consequences

- TUI handles mixed binary/JSON event streams without crashing
- State is always derived from the explicit snapshot poll, not from event payloads

## Open Tail

*(none)*

## Evidence

- transcript lines 2420-2435

