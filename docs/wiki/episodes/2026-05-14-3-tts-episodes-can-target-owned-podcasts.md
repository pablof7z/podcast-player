---
type: episode-card
date: 2026-05-14
session: 84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/84c4d49c-d034-4d2e-8e1e-dfd5a4453b2d.jsonl
salience: product
status: active
subjects:
  - tts-episode-generation
  - agent-owned-podcast
  - nip-74
supersedes: []
related_claims: []
source_lines:
  - 3640-3670
  - 4018-4048
captured_at: 2026-06-12T12:27:32Z
---

# Episode: TTS episodes can target owned podcasts with auto-Nostr-publish

## Prior State

generate_tts_episode always published to the hardcoded 'Agent Generated' virtual podcast; there was no way to target a user-created owned podcast, and no NIP-74 episode event was ever published for TTS content

## Trigger

Codex review identified that TTS cannot target owned shows and proposed adding podcast_id to the tool schema

## Decision

Added optional podcast_id parameter to generate_tts_episode, threaded targetPodcastID: UUID? through TTSPublisherProtocol → AgentTTSComposer → AgentGeneratedPodcastService.publishEpisode, with validation that the ID points to an agent-owned show and automatic NIP-74 episode publishing when the target podcast is public

## Consequences

- Agent can now create TTS episodes in user-owned podcast feeds, not just the default synthetic one
- LiveYouTubeIngestionAdapter call site updated to pass nil (preserving existing behavior)
- Public owned podcasts auto-publish episode events to Nostr relays when TTS targets them

## Open Tail

*(none)*

## Evidence

- transcript lines 3640-3670
- transcript lines 4018-4048

