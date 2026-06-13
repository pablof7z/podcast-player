---
type: episode-card
date: 2026-05-13
session: f11c47b8-a7bd-47d3-9eb0-79dd02904d04
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f11c47b8-a7bd-47d3-9eb0-79dd02904d04.jsonl
salience: product
status: active
subjects:
  - agent-tool-surface
  - playback-tool-unification
supersedes: []
related_claims: []
source_lines:
  - 3305-3925
captured_at: 2026-06-12T12:10:38Z
---

# Episode: Unify play_external_episode into play_episode

## Prior State

The agent exposed two separate playback tools: `play_episode` (for library episodes via `episode_id`) and `play_external_episode` (for any public episode via `audio_url`/`title`). This was a historical artifact from an earlier split between subscribed and unsubscribed podcast playback.

## Trigger

User flagged that the agent was still reporting access to `play_external_episode` — the prior unification had been incomplete or never completed: 'didn't we unify these playback tools???!'

## Decision

Fold `play_external_episode` entirely into `play_episode`. The single tool now accepts either `episode_id` (library path) or `audio_url`+`title` (external path) as mutually exclusive identifier patterns. `PodcastNames.playExternalEpisode` constant removed; dispatch case removed; schema entry removed; `AgentTools+PodcastExternal.swift` handler deleted. The agent's entire playback surface is now four tools: `play_episode`, `pause_playback`, `set_playback_rate`, `set_sleep_timer`.

## Consequences

- External plays gain `end_seconds` (bounded-segment playback) which previously only library episodes supported
- Internal routing still bifurcates (`playback.playEpisode` vs `playback.playExternalEpisode`) but the LLM sees one verb
- Schema test had to be updated because the set of tool names changed
- Fewer tool choices reduces LLM confusion when the user says 'play that episode'

## Open Tail

*(none)*

## Evidence

- transcript lines 3305-3925

