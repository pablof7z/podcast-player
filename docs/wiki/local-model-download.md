---
title: Local Model Download
slug: local-model-download
topic: data-persistence
summary: Model downloads use plain `URLSession` with no authentication, pulling `.litertlm` files from HuggingFace's ungated `litert-community` CDN, with commit SHAs pin
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-03
updated: 2026-06-12
verified: 2026-06-03
compiled-from: conversation
sources:
  - session:4dd36f3c-199e-4d1b-9f63-2f86c41e2f2a
  - session:e1ab0629-64bc-4383-bd22-c0843ca16a99
---

# Local Model Download

## Model Download

Model downloads are routed through a unified Rust `DownloadQueue` (shared singleton, not rebuilt per screen appearance, so iOS background-session callbacks remain wired to a single manager) with a `DownloadKind` discriminant (`Episode`/`LocalModel`), which replaces the bespoke `LocalModelDownloadManager`. The `DownloadKind` enum on the wire uses `#[serde(default, skip_serializing_if = "is_episode")]` so episode JSON remains byte-identical (no `kind` key emitted). Model downloads bypass the episode auto-download/revalidation machinery via a direct `DownloadLocalModel` action that enqueues with `kind LocalModel`. Downloads match completed files by download URL rather than by on-disk basename, because the on-disk name (e.g. `gemma4-e2b`) never equals the remote URL filename (e.g. `gemma-4-E2B-it`). Completion persistence branches on kind: episodes call `set_local_path`; model downloads skip it (the file on disk is the source of truth at `LocalModels/<id>.litertlm`). The unified download manager gives models resume/retry/background support for free by inheriting the episode DownloadCapability's existing resume implementation, eliminating the need to recover kind by probing resume blobs on disk. (Previously: `resumeDownload` recovers kind by probing which resume blob exists on disk, fixing the latent bug where kind was lost on resume, superseded — see episode-download-service.)

<!-- citations: [^4dd36-6] [^e1ab0-9] -->
## Model Size and Delivery

The Gemma4-E2B model is approximately 2.6 GB on disk and is delivered as a post-install download, not bundled in the IPA. Models share the episode queue's `max_concurrent=3` slots, which can cause head-of-line latency when multi-GB model transfers occupy slots during episode downloads.

<!-- citations: [^4dd36-7] [^e1ab0-10] -->
