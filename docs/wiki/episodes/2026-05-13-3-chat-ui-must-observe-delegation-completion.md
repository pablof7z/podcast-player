---
type: episode-card
date: 2026-05-13
session: 9f3b9a0a-d40b-4658-ad51-c157a7780612
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f3b9a0a-d40b-4658-ad51-c157a7780612.jsonl
salience: product
status: active
subjects:
  - agent-chat-session
  - delegation-ui-update
  - notification-center
supersedes: []
related_claims: []
source_lines:
  - 2194-2217
  - 2313-2370
captured_at: 2026-06-12T12:19:54Z
---

# Episode: Chat UI must observe delegation completion to reload messages

## Prior State

Headless AgentChatSession persisted messages to ChatHistoryStore.shared, but the UI's live AgentChatSession instance held a separate messages array with no observer on external changes — user had to close and reopen the chat to see delegation responses

## Trigger

User reported: 'The agent replied but the agent in the app didn't see the reply' — the friend agent's response was processed but the UI never refreshed

## Decision

Post NotificationCenter .agentDelegationDidComplete with the conversation UUID after headless run completes; AgentChatSession observes it and reloads messages from ChatHistoryStore when the IDs match

## Consequences

- Chat window updates in real time when a delegation response arrives
- AgentChatSession now has an external observation channel for cross-instance state changes

## Open Tail

*(none)*

## Evidence

- transcript lines 2194-2217
- transcript lines 2313-2370

