---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: product
status: active
subjects:
  - agent-tool-errors
  - playback-deps
  - honest-failure
supersedes: []
related_claims: []
source_lines:
  - 589-640
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Agent tool errors must be honest, not fake-success

## Prior State

setPlaybackRate returned 1.0, setSleepTimer returned "Unavailable" (accepted as valid label), and pausePlayback returned Void — all three lied to the LLM agent when the playback host was missing, causing the agent to believe actions succeeded that never happened.

## Trigger

Exhaustive codebase audit revealed these silent-success guards in LivePodcastAgentToolDeps.swift; the LLM had no way to know playback was unavailable.

## Decision

All three return Optional/Bool (Double?, String?, Bool); dispatch layer guards on the result and emits toolError("Playback is unavailable."). Protocol, live impl, and mocks all updated.

## Consequences

- LLM agent now receives honest error signals and can inform the user or retry appropriately
- Any agent conversation that relied on implicit success will now surface the real state
- MockPlayback in tests still returns success values (always-present playback)

## Open Tail

- openScreen tool is still a no-op log; schema advertises it to the LLM but impl does nothing (blocked on nav router)

## Evidence

- transcript lines 589-640

