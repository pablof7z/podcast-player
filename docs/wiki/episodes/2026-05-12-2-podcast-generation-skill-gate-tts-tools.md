---
type: episode-card
date: 2026-05-12
session: 9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9d55e84d-b4cf-4c53-80c2-3cbdd80e54a1.jsonl
salience: product
status: active
subjects:
  - podcast-generation-skill
  - tts-tools
  - list-available-voices
  - skill-gating
supersedes: []
related_claims: []
source_lines:
  - 1-3
  - 687-693
  - 747-753
  - 771-777
captured_at: 2026-06-12T11:58:34Z
---

# Episode: Podcast Generation Skill: Gate TTS Tools and Voice Knowledge Behind Activation

## Prior State

generate_tts_episode and configure_agent_voice were always-on tools in the podcast schema; the system prompt always included a paragraph teaching the agent how to compose TTS episodes. Voice information was not queryable.

## Trigger

User directive to start with podcast generation as the first built-in skill, providing 'information on how to generate chapters that are associated with the episode we generate' and knowledge of available voices.

## Decision

Created PodcastGenerationSkill gating generate_tts_episode, configure_agent_voice, and a new list_available_voices tool. Removed the always-on TTS paragraph from the system prompt. The skill's manual covers turn structure → chapter mapping, voice selection, emotion cues, snippet sourcing, and a quality gate.

## Consequences

- Agent no longer sees TTS tools until it calls use_skill(podcast_generation) — reduces every-turn prompt weight
- New list_available_voices tool gives the agent discoverable voice options only when the skill is active
- The TTS instruction paragraph is replaced by skill-manual injection only on activation
- dispatchPodcast rejects generate_tts_episode/configure_agent_voice/list_available_voices calls when podcast_generation skill is not enabled

## Open Tail

*(none)*

## Evidence

- transcript lines 1-3
- transcript lines 687-693
- transcript lines 747-753
- transcript lines 771-777

