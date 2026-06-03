---
title: Embeddings and Vector DB
slug: embeddings-and-vector-db
summary: The current RAG embedding pipeline calls OpenRouter for embeddings.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-03
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:55bedfc3-dd9e-4b1c-b7d7-cea0c699d4d1
---

# Embeddings and Vector DB

## Current RAG Embedding Pipeline

The current RAG embedding pipeline calls OpenRouter for embeddings. [^55bed-1]


## Evaluated On-Device Embedding Approaches

Apple's `NLEmbedding` provides zero-download, 250-dim Word2Vec-style embeddings but has significantly worse quality than sentence transformers for multi-sentence chunks and misses semantic matches. Reusing the Gemma model for embeddings avoids extra downloads but yields mediocre quality without fine-tuning and has high per-chunk latency. [^55bed-2]

## Recommended Approach: Core ML MiniLM

Core ML is the recommended approach for on-device iPhone embeddings. The `all-MiniLM-L6-v2` model can be converted to a Core ML `.mlpackage` via `coremltools` to produce 384-dim sentence embeddings. The model file is 23 MB regardless of whether it is deployed as Core ML or ONNX. Core ML MiniLM natively supports iPhone (iOS 11+), runs on the Neural Engine for A12+ chips (iPhone XS or newer), and is the most battle-tested path for on-device embeddings. Although the Core ML approach places embedding generation in Swift/Core ML rather than the Rust kernel—breaking the pattern of keeping business logic in Rust—embedding generation is an infrastructure concern rather than business logic, making this tradeoff acceptable. [^55bed-3]

## Alternative: ONNX Runtime in Rust

The `ort` ONNX Runtime Rust bindings can run `all-MiniLM-L6-v2` as an `.onnx` file entirely within the Rust kernel, keeping embeddings aligned with the existing architecture philosophy. However, while ONNX Runtime provides prebuilt iOS arm64 libraries, integrating them into a Rust kernel's iOS cross-compilation requires linking the ORT static framework at the Xcode level and adds non-trivial build complexity. Because embedding generation is an infrastructure concern, this build complexity is unjustified compared to the Core ML path. [^55bed-4]
## See Also

