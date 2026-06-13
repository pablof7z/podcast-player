---
type: episode-card
date: 2026-05-12
session: 514d3552-fbf6-4382-9488-8ba8b4289797
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/514d3552-fbf6-4382-9488-8ba8b4289797.jsonl
salience: product
status: active
subjects:
  - episode-generation-source
  - agent-tts-pipeline
  - episode-codable
supersedes: []
related_claims: []
source_lines:
  - 1531-1566
captured_at: 2026-06-12T12:01:00Z
---

# Episode: Episode Generation Source Provenance

## Prior State

Episodes had no provenance field. Agent-generated podcasts carried no record of which conversation (Nostr peer or in-app chat) triggered their creation. The TTS generation pipeline had no mechanism to accept or persist origin metadata.

## Trigger

User request: 'would be really cool if, when we play a podcast that was agent-generated, we link to the source where that generation was triggered' — requiring episodes to carry their generation origin.

## Decision

Added `Episode.GenerationSource` enum with `.nostr(rootEventID:peerPubkeyHex:)` and `.inAppChat(conversationID:)` cases, with manual Codable using a `type` discriminator and `decodeIfPresent` for backward compatibility. Threaded `generationSource` parameter through `TTSPublisherProtocol`, `AgentTTSComposer`, `AgentGeneratedPodcastService.publishEpisode`, and `AgentTools+TTS` build path. Added `chatConversationID` to `PodcastAgentToolDeps` so in-app chat sessions can stamp the current conversation ID per-dispatch.

## Consequences

- All new agent-generated episodes persist their origin conversation; old episodes decode with `generationSource = nil`
- `PodcastAgentToolDeps` gained a new `withChatConversationID(_:)` copy method; `AgentChatSession+Turns` now passes it on every dispatch
- Every `TTSPublisherProtocol` conformer (production + mock) must accept the new `generationSource` parameter
- `Episode` is `Hashable`; `GenerationSource` must also conform to `Hashable` (caught as build error)

## Open Tail

*(none)*

## Evidence

- transcript lines 1531-1566

