---
title: Wiki Generation Pipeline
slug: wiki-generation-pipeline
topic: wiki-generation
summary: Empty RAG results still persist a hollow wiki page with `confidence=0.5` because `WikiPrompts.renderChunks` falls back to 'no evidence available' and the model
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-06-12
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:8bfa1b91-b40c-44b3-acb9-245b36f4c841
  - session:rollout-2026-05-09T14-56-23-019e0c98-8803-7ef0-b7a2-bf0b605a2360
  - session:rollout-2026-05-10T20-45-04-019e12fe-1fe8-7d93-a41f-0cebfa991f0a
---

# Wiki Generation Pipeline

## Hollow-page persist from empty RAG results

Empty RAG results still persist a hollow wiki page with `confidence=0.5` because `WikiPrompts.renderChunks` falls back to 'no evidence available' and the model returns empty sections that the verifier keeps. (Previously: `WikiGenerator.compileTopic`/`compilePerson`/`compileShow` and `audit(prior:)` threw `insufficientEvidence` when RAG scope had no chunks, preventing hollow-page persist.) <!-- [^7f076-17] -->

RAGChunk.speaker is hardcoded to `nil` in RAGService+Adapters, starving the 'Who discussed it' section of speaker information. <!-- [^7f076-18] -->

The briefings-scheduler wiki article, having had its body deleted, must contain a tombstone rather than remaining as an empty page with a misleading _index.md summary. <!-- [^8bfa1-6] -->

## Commit staging and formatting

Auto-generated derived cache trees (docs/wiki/) are excluded from commits and should be gitignored rather than committed, so wiki articles need not be staged with _index.md. (Previously: The 18 new untracked wiki articles must be staged in the same commit as _index.md to prevent broken internal links, superseded — see agent-worktree-cleanup.) Wiki articles must include a blank line before ATX headings for proper CommonMark rendering (affected: nmp-integration-rules.md and security-and-constraints.md). <!-- [^8bfa1-7] -->

## Wiki Generation Pipeline

The product generates LLM-wiki-like knowledge bases from podcast content. Product wikis are stored under docs/wiki. <!-- [^rollo-21] -->


RAG is substring search, wiki is placeholder generation, and briefings are stubs; these must not be considered real output or feature parity. (Previously: Briefing/RAG/wiki paths produce real output instead of falling back to fixtures. <!--  -->, superseded — see nmp-codegen.)
## Adjacent research scope

The adjacent research wiki covers Podcasting 2.0 metadata, source-grounded generated audio/video study artifacts, highlight export loops, privacy-friendly public analytics, and ambient iOS controls, but does not suggest monetization/payment tooling as an agent direction. <!-- [^rollo-22] -->
