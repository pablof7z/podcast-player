---
title: Threading Inference Service
slug: threading-inference-service
topic: agent-system
summary: "ThreadingTopicListView seeds mock threading data into the live UI via `service.seedMockIfEmpty(store:)` when no inference results exist"
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-12
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:0f3f24f7-54de-49f8-b160-a92f735f6a00
  - session:04b5f843-fdbe-4aa1-ae41-6770eac82957
---

# Threading Inference Service

## Mock Data Seeding

ThreadingTopicListView seeds mock threading data into the live UI via `service.seedMockIfEmpty(store:)` when no inference results exist. The seed mock method is guarded with `#if DEBUG` so TestFlight users no longer see fake ketogenic-diet topics. <!-- [^0f3f2-70] -->

## Inference Recomputation

ThreadingInferenceService.recompute(store:) is a no-op stub. RAG is implemented as substring search (no longer deferred), but this does not constitute feature parity; noun-phrase extraction and contradiction detection status remain unspecified. (Previously: RAG semantic search, noun-phrase extraction, and contradiction detection are all deferred. <!--  -->, superseded — see nmp-codegen.)

Issue #320 (Android 500ms poll) is already fixed in main by PR #345; the poll was replaced with a blocking-wait push channel and no polling remains. <!-- [^04b5f-7] -->
