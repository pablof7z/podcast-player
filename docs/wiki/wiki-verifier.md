---
title: Wiki Verifier
slug: wiki-verifier
topic: wiki-generation
summary: WikiVerifier accepts `isGeneralKnowledge` in any section, but the brief restricts it to Definition paragraphs only.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:7f076ca6-6975-44ae-9848-d41832e499f0
  - session:rollout-2026-05-11T09-10-31-019e15a8-97f5-7fc2-9daf-4c834d1999b0
---

# Wiki Verifier

## General-Knowledge Restriction

WikiVerifier accepts `isGeneralKnowledge` in any section, but the brief restricts it to Definition paragraphs only. <!-- [^7f076-24] -->

The gate should require `section.kind == .definition`; outside Definition sections, general-knowledge claims are dropped. <!-- [^7f076-25] -->

## Fuzzy-Match Confidence Issue

WikiVerifier's 60% token-overlap fuzzy match assigns `.medium` confidence to paraphrased claims rather than dropping them, contravening the brief's provenance requirement. <!-- [^7f076-26] -->

## Missing Adversarial Pass and Unresolved Verdict

WikiVerifier has no adversarial counter-evidence pass and no `unresolved` verdict, meaning the Consensus vs Contradictions layout cannot be honestly populated. <!-- [^7f076-27] -->

## Citation Resolution Mechanism

Wiki citation verification resolves by deterministic episode and time-span lookup through `VectorIndex`, removing the broad `query: "."` RAG workaround. <!-- [^rollo-123] -->
