---
type: episode-card
date: 2026-05-11
session: 7f076ca6-6975-44ae-9848-d41832e499f0
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7f076ca6-6975-44ae-9848-d41832e499f0.jsonl
salience: root-cause
status: active
subjects:
  - wiki-product-framing
  - wiki-triggers
  - auto-compile-gap
supersedes: []
related_claims: []
source_lines:
  - 5696-5818
captured_at: 2026-06-12T11:54:11Z
---

# Episode: Wiki feature is a manual page-compiler, not a self-maintaining encyclopedia

## Prior State

The UX-04 brief and documentation describe the wiki as 'a self-maintaining, citation-grounded encyclopedia compiled from your listening' — a system that auto-populates from listening signal

## Trigger

Five-agent audit discovered that `WikiTriggers.jobsForNewEpisode` explicitly refuses to create pages — it only refreshes ones the user manually compiled first. The auto-refresh wiring shipped this session reinforces a manual workflow, not an automatic one.

## Decision

Finding: the feature as-implemented is a manual page-compiler with auto-refresh, not a self-maintaining encyclopedia. Conviction rated 3/10 as-is, rising to 6–7/10 only if auto-compile-from-listening signal ships. Three alternative framings proposed: (A) topic-by-speaker panel folded into Search, (B) passive disagreement feed surfacing where hosts contradict each other, (C) invisible agent memory via query_wiki.

## Consequences

- The Wiki tab requires the user to know what to ask before the system can help — the core JTBD ('revisit a topic threaded through dozens of episodes') is structurally unmet
- Dual-link [[slug]] resolver is 0/5 implemented — pages are isolated, not a graph
- Contest workflow (isContestedByUser) has zero UI callers — the feedback loop is unreachable
- RAGChunk.speaker is hardcoded to nil, starving the 'Who's discussed it' section
- Agent E's recommendation: Framing B (disagreement feed) reuses the trigger pipeline already built

## Open Tail

- Strategic decision pending: reframe the feature (A or B), fix the auto-compile hole, or mothball with bug fixes
- If keeping current framing: WikiTriggers must be allowed to create pages from topics crossing a frequency threshold

## Evidence

- transcript lines 5696-5818

