---
type: episode-card
date: 2026-05-13
session: 3b6253ac-ef01-489b-a3dc-a0a5932e8d0a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/3b6253ac-ef01-489b-a3dc-a0a5932e8d0a.jsonl
salience: product
status: active
subjects:
  - agent-scheduled-tasks
  - schedule-task-tool
  - agent-task-runner
supersedes: []
related_claims: []
source_lines:
  - 1228-1510
captured_at: 2026-06-12T12:14:39Z
---

# Episode: Agent scheduled recurring tasks capability

## Prior State

The agent could only respond to immediate, real-time user requests in a chat session. There was no mechanism for the agent to perform recurring automated actions on the user's behalf.

## Trigger

Feature implementation to give the agent persistent, recurring task scheduling ability — the agent can now be asked things like 'every day, search Hacker News for interesting podcasts and add them to my queue.'

## Decision

Added three new agent tools (schedule_task, cancel_scheduled_task, list_scheduled_tasks) accepting both interval_seconds and named cadences (hourly/daily/weekly). A new AgentScheduledTask domain model and AgentScheduledTaskRunner fire due tasks headlessly via AgentChatSession when the app foregrounds. Miss-once semantics (mark before execute) prevent double-firing. PodcastAgentToolDeps was refactored so the headless runner gets pre-built podcast dependencies.

## Consequences

- Users can instruct the agent to perform recurring automated actions without being present in chat
- Tasks execute on app foreground when their nextRunAt has passed
- AgentChatSession gained drainPendingContext: Bool (defaults true) so scheduled runs don't consume pending user context
- AgentRunSource gained .scheduledTask case for run logging
- PodcastAgentToolDeps injection path refactored to support both interactive chat and headless runner contexts

## Open Tail

- No server-side push yet — tasks only check on foreground, not in background
- No UI for users to view/manage scheduled tasks outside the agent chat

## Evidence

- transcript lines 1228-1510

