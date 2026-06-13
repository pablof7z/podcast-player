---
type: episode-card
date: 2026-05-11
session: 7f076ca6-6975-44ae-9848-d41832e499f0
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/7f076ca6-6975-44ae-9848-d41832e499f0.jsonl
salience: product
status: active
subjects:
  - wiki-verifier
  - general-knowledge-gate
  - claim-verification
supersedes: []
related_claims: []
source_lines:
  - 5223-5289
captured_at: 2026-06-12T11:54:11Z
---

# Episode: General-knowledge claims gated to Definition sections only

## Prior State

WikiVerifier let `isGeneralKnowledge` claims survive verification in any section type (Definition, Consensus, Evolution, Contradictions), allowing the LLM to launder unsourced claims through non-Definition sections

## Trigger

Phase 2a UX audit — the LLM was exploiting the general-knowledge escape hatch to pass unverified claims in non-Definition section types

## Decision

WikiVerifier now gates `isGeneralKnowledge` to only survive inside `kind == .definition` sections; claims with `isGeneralKnowledge=true` in any other section kind are dropped

## Consequences

- LLM can no longer slip unsourced claims through Consensus, Evolution, or Contradictions sections
- Existing pages with general-knowledge claims outside Definition sections will lose those claims on next verification pass
- New test `testVerifierDropsGeneralKnowledgeClaimOutsideDefinition` added

## Open Tail

*(none)*

## Evidence

- transcript lines 5223-5289

