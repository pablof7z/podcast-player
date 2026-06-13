---
type: episode-card
date: 2026-05-11
session: 7f076ca6-6975-44ae-9848-d41832e499f0
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7f076ca6-6975-44ae-9848-d41832e499f0.jsonl
salience: root-cause
status: active
subjects:
  - wiki-auto-refresh
  - wiki-response-parser
  - wiki-storage-race
  - wiki-audit-prompt
supersedes: []
related_claims: []
source_lines:
  - 5776-5784
captured_at: 2026-06-12T11:54:11Z
---

# Episode: Three critical bugs in auto-refresh pipeline

## Prior State

Auto-refresh wiring was just shipped this session (Phase 1a), gated behind `wikiAutoGenerateOnTranscriptIngest` (default off)

## Trigger

Agent D pipeline audit found three bugs in freshly-shipped code

## Decision

Bugs identified but not yet fixed; auto-refresh toggle must stay off until they're resolved

## Consequences

- Bug 1: WikiResponseParser defaults page title to slug when LLM omits `title` — every auto-refresh corrupts the page title to a lowercase slug
- Bug 2: WikiStorage.updateInventory uses `try?` on inventory load with no lock — up to 3 concurrent executor jobs can race, potentially wiping all other pages from the wiki home
- Bug 3: WikiPrompts.audit doesn't include the prior page body — auto-refresh silently downgrades high-confidence prior claims because the LLM can't 'retain still-supported claims, drop newly contradicted ones'
- The auto-refresh toggle is a footgun until all three are patched

## Open Tail

- Must fix title-corruption, inventory-race, and audit-prompt before enabling auto-refresh
- Empty-RAG guard (`insufficientEvidence`) was added to WikiGenerator.audit to prevent clobbering usable prior pages

## Evidence

- transcript lines 5776-5784

