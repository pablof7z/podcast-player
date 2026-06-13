---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: root-cause
status: active
subjects:
  - ai-inbox-triage
  - episode-persistence
  - feed-refresh
supersedes: []
related_claims: []
source_lines:
  - 1505-1513
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Triage state must survive feed-refresh upserts

## Prior State

upsertEpisodes preserved playbackPosition, played, and other playback fields across RSS merge — but triageDecision, triageRationale, and triageIsHero were not in the merge block, so every feed refresh reset them to nil.

## Trigger

Codex review identified that triage state was being wiped on every refresh (line 919-921). Archived episodes would reappear as untriaged, and the LLM would re-classify them, causing decisions to flicker.

## Decision

Added triageDecision, triageRationale, and triageIsHero to the merge-preservation block in AppStateStore+Episodes.swift.

## Consequences

- Any future triage fields added to Episode must be added to the same merge block, or they will be silently wiped on refresh
- The merge block is now the single location where all persistent triage state is preserved across RSS merges

## Open Tail

*(none)*

## Evidence

- transcript lines 1505-1513

