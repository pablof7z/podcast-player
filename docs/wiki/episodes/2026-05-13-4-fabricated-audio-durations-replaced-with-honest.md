---
type: episode-card
date: 2026-05-13
session: 0f3f24f7-54de-49f8-b160-a92f735f6a00
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/0f3f24f7-54de-49f8-b160-a92f735f6a00.jsonl
salience: root-cause
status: active
subjects:
  - agent-tts-composer
  - audio-duration
  - briefing-integrity
supersedes: []
related_claims: []
source_lines:
  - 836-879
captured_at: 2026-06-12T12:08:20Z
---

# Episode: Fabricated audio durations replaced with honest errors

## Prior State

AgentTTSComposer.audioDuration returned 1.0s or 60.0s on AVURLAsset failure, and resolveEpisodeTitle returned literal "Clip" for missing episodes. These fictional values silently corrupted chapter math and briefing structure.

## Trigger

Audit identified the hardcoded fallbacks; combined with placeholder titles, briefings could contain chapters with wrong durations and generic titles.

## Decision

audioDuration now throws AudioDurationError (.zeroDuration / .assetLoadFailed). buildTracks catches per-turn, logs the bad URL, skips that turn, only adds surviving turns. resolveEpisodeTitle returns String? and falls back to "Quote at M:SS" using actual start offset. If every turn fails, throws AgentTTSError.noPlayableContent.

## Consequences

- Briefings will never ship with fabricated durations or generic 'Clip' titles
- Partial briefings are possible (surviving turns only) — parallel arrays stay in lockstep
- Completely broken briefings now fail loudly instead of producing corrupt output
- Dead guard that silently skipped zero-duration chapters is removed

## Open Tail

- Snippet duration = end - start does not validate end > start; negative durations would still corrupt chapter math
- LivePodcastAgentToolDeps.swift is 664 lines — 164 over the 500-line hard limit

## Evidence

- transcript lines 836-879

