---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - threading-mock-data
  - debug-guard
supersedes: []
related_claims: []
source_lines:
  - 695-712
captured_at: 2026-06-12T12:08:20Z
---

# Episode: TestFlight must not show debug mock data

## Prior State

ThreadingTopicListView.seedMockIfEmpty was unconditionally seeding fake 'ketogenic-diet' topics, visible to TestFlight users.

## Trigger

Audit found the unguarded mock seeding.

## Decision

Wrapped seedMockIfEmpty with #if DEBUG so TestFlight/release builds no longer show fake topics.

## Consequences

- TestFlight and production users no longer see mock threading topics
- Debug builds still seed mock data for development

## Open Tail

*(none)*

## Evidence

- transcript lines 695-712

