---
type: episode-card
date: 2026-05-15
session: d0447a6c-e8a4-4913-a5bd-cd462c96487a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0447a6c-e8a4-4913-a5bd-cd462c96487a.jsonl
salience: product
status: active
subjects:
  - publish-episode-tool
  - nip-74-episode-publishing
  - agent-tools
supersedes: []
related_claims: []
source_lines:
  - 1123-1146
captured_at: 2026-06-12T12:33:39Z
---

# Episode: New publish_episode agent tool for standalone Nostr episode publishing

## Prior State

Episodes could only be published to Nostr implicitly via generate_tts_episode with a podcast_id parameter. There was no standalone tool to publish an already-existing episode as a NIP-74 kind:30075 event.

## Trigger

Need for agent to selectively publish existing episodes to Nostr independently of TTS generation.

## Decision

Added a dedicated publish_episode agent tool with its own schema, handler, and dispatch routing. The tool validates the podcast is agent-owned and public, then publishes a kind:30075 event via NostrPodcastPublisher, returning naddr on success or a descriptive error when prerequisites aren't met.

## Consequences

- Agent can now publish episodes to Nostr at any time after creation, not only during TTS generation
- New tool schema must be registered in the podcast dispatch table alongside existing tools
- Test mocks and makeDeps across 5 test files needed ownedPodcasts parameter

## Open Tail

*(none)*

## Evidence

- transcript lines 1123-1146

