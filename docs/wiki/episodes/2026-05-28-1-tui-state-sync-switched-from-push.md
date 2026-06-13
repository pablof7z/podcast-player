---
type: episode-card
date: 2026-05-28
session: 31d36c85-992e-43d0-a31c-ab1c8e43344c
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/31d36c85-992e-43d0-a31c-ab1c8e43344c.jsonl
salience: architecture
status: superseded
subjects:
  - podcast-tui
  - snapshot-polling
  - flatbuffer-bridge
supersedes: []
related_claims: []
source_lines:
  - 2265-2283
  - 1882-1884
  - 1929-1930
  - 1958-1958
  - 2128-2155
  - 2829-2855
captured_at: 2026-06-12T12:53:26Z
---

# Episode: TUI state sync switched from push-based JSON events to pull-based snapshot polling

## Prior State

The TUI received kernel state updates through NmpUpdateBridge as JSON-serialised event payloads. Each tick, apply_nmp_event parsed event.payload as JSON via serde_json::from_str and applied it to AppState.

## Trigger

Testing the TUI revealed that NMP kernel sends FlatBuffer binary frames, not JSON strings. The bridge was corrupting the data by treating raw bytes as UTF-8, producing 'snapshot parse error: expected value at line 1 column 1' on every tick. Search results never appeared because state never updated.

## Decision

Replaced push-based JSON event consumption with pull-based snapshot polling: on each 250ms tick, the main loop calls nmp_app_podcast_snapshot / nmp_app_podcast_snapshot_rev (matching the iOS shell pattern). When rev changes, the JSON snapshot is applied directly via a new apply_snapshot_json method. FlatBuffer frames from the bridge are now silently ignored since they are expected to be non-JSON.

## Consequences

- NmpUpdateBridge still fires but its payloads are treated as opaque binary — no longer a source of UI state
- State freshness is now gated by the 250ms tick interval rather than kernel event arrival
- The iOS shell and TUI shell now share the same snapshot-polling doctrine, making future shell implementations consistent
- apply_snapshot_json exists as a separate entry point from apply_nmp_event, codifying that polled snapshots and pushed events have different trust levels

## Open Tail

- The current repo state has diverged from the working snapshot — main.rs calls state.apply_podcast_update(update) which does not exist in app.rs, and Tab::Inbox is unhandled, so the code does not compile as-is

## Evidence

- transcript lines 2265-2283
- transcript lines 1882-1884
- transcript lines 1929-1930
- transcript lines 1958-1958
- transcript lines 2128-2155
- transcript lines 2829-2855

