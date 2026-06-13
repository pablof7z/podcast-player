---
type: episode-card
date: 2026-06-08
session: c33b9adb-9d1a-4717-9314-b45a61e6cbc3
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c33b9adb-9d1a-4717-9314-b45a61e6cbc3.jsonl
salience: product
status: active
subjects:
  - coreml-embeddings
  - embedding-provider
  - on-device-ml
supersedes: []
related_claims: []
source_lines:
  - 391-406
captured_at: 2026-06-12T13:31:41Z
---

# Episode: Core ML on-device embeddings pipeline added (dormant)

## Prior State

No on-device embedding capability existed; all embedding computation was routed to external API (OpenRouter).

## Trigger

Issue #236 requesting Core ML embeddings for on-device inference to reduce latency and API dependency.

## Decision

Built Core ML all-MiniLM-L6-v2 embeddings pipeline (WordPieceTokenizer + LocalEmbeddingsClient + CoreMLEmbeddingProvider) with OpenRouter fallback. Pipeline is intentionally inert until the .mlpackage asset is published and the vector index migrates to 384-dim.

## Consequences

- New on-device embedding path exists but is dormant until activation conditions are met
- Activation tracked in BACKLOG as coreml-embeddings-activation
- Confirmed that CI regenerates project via tuist generate — pbxproj is NOT the build input, Project.swift is the canonical source of truth

## Open Tail

- Vector index migration to 384-dim needed for activation
- .mlpackage asset must be published to bundle

## Evidence

- transcript lines 391-406

