---
type: episode-card
date: 2026-05-13
session: 3b6253ac-ef01-489b-a3dc-a0a5932e8d0a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/3b6253ac-ef01-489b-a3dc-a0a5932e8d0a.jsonl
salience: architecture
status: active
subjects:
  - chat-conversation-isScheduledTask
  - chat-history-mostRecent
supersedes: []
related_claims: []
source_lines:
  - 1246-1252
captured_at: 2026-06-12T12:14:39Z
---

# Episode: Scheduled task conversations excluded from auto-resume

## Prior State

ChatHistoryStore.mostRecent returned the most recent conversation regardless of type, which would cause a scheduled task's headless conversation to become the one the user resumes when opening the chat sheet.

## Trigger

Adding scheduled recurring tasks would produce invisible automated conversations that could hijack the user's auto-resume path, landing them in a robotic task run instead of their last human conversation.

## Decision

Added isScheduledTask: Bool to ChatConversation (forward-compatible, defaults to false on decode). ChatHistoryStore.mostRecent now skips isScheduledTask conversations so the user always resumes their last human conversation.

## Consequences

- Scheduled task conversations are persisted but hidden from the normal chat resume flow
- Existing conversations decode with isScheduledTask=false, preserving backward compatibility
- The chat history view still shows all conversations — only mostRecent filtering changed

## Open Tail

*(none)*

## Evidence

- transcript lines 1246-1252

