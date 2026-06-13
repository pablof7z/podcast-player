---
type: episode-card
date: 2026-05-11
session: 7f076ca6-6975-44ae-9848-d41832e499f0
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7f076ca6-6975-44ae-9848-d41832e499f0.jsonl
salience: product
status: active
subjects:
  - chapter-compiler-model-role
  - ai-chapters
  - settings-model-separation
supersedes: []
related_claims: []
source_lines:
  - 87-113
captured_at: 2026-06-12T11:54:11Z
---

# Episode: Chapter compilation needs its own model role, not shared wikiModel

## Prior State

AIChapterCompiler reuses `settings.wikiModel` — the same model, API key, and settings UI as the wiki pipeline. No separate 'chapter compile model' exists.

## Trigger

User directive: 'we need a role specific for this' after learning chapters and wiki share one model setting

## Decision

A dedicated model role for chapter compilation will be created in Settings, distinct from the wiki model. Not yet implemented in this session.

## Consequences

- Users will be able to configure chapter compilation independently from wiki generation
- Chapters will no longer silently no-op when the wiki provider API key is missing
- Settings UI needs a new LLM role row for 'Chapters'

## Open Tail

- Implementation not started — needs new Settings field, LLMSettingsView row, and AIChapterCompiler wiring

## Evidence

- transcript lines 87-113

