---
title: Local Embedding RAG
slug: local-embedding-rag
topic: local-model-inference
summary: Local embedding for RAG on iPhone uses Core ML with the all-MiniLM-L6-v2 sentence transformer model (~23 MB), producing 384-dim embeddings with Neural Engine ac
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-12
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
---

# Local Embedding RAG

## Local Embedding Model

Local embedding for RAG on iPhone uses Core ML with the all-MiniLM-L6-v2 sentence transformer model (~23 MB), producing 384-dim embeddings with Neural Engine acceleration on A12+ chips. The MiniLM tokenizer uses WordPiece (not BPE); swift-transformers handles this correctly. Android will use a different local embedding approach than iPhone. On-device embeddings (issue #236) use this model with an OpenRouter fallback (PR #350). The Core ML embeddings pipeline is intentionally inert until the .mlpackage asset is published and the vector index migrates to 384-dim, tracked in BACKLOG as coreml-embeddings-activation.

<!-- citations: [^55bed-5] [^c33b9-3] -->
## Architecture: Rust / Swift FFI Split

Rust owns the EmbeddingBackend trait and provider selection; Swift registers a Core ML embedding callback at startup, and Rust calls it via FFI when the local provider is configured. When OpenRouter is configured, Rust calls it directly via HTTP. For text generation, Swift simply renders streamed tokens without knowing what provider handles the request; Rust owns inference through the LlmBackend trait (OpenRouterBackend, OllamaBackend, LocalModelBackend). (Previously: This follows the same FFI callback pattern as the existing generateText/LiteRT integration: Swift owns inference infrastructure, Rust owns what to ask and what to do with the answer. <!--  -->, superseded — see llm-backend-abstraction.)

## FFI Performance

The FFI overhead for passing a 384-dim float vector (~1.5 KB) across the Swift/Rust boundary is negligible (~0.1 ms) compared to Core ML inference time (5–20 ms). <!-- [^55bed-7] -->

## FFI Naming Convention

The FFI function for registering the Core ML embedding callback follows the naming convention nmp_app_podcast_set_embedding_fn, scoped to the podcast handle, not a generic NMP capability. The NMP C ABI requires globally unique symbol names using the nmp_app_podcast_ prefix as a namespace to prevent collisions in the flat symbol table. <!-- [^55bed-8] -->
