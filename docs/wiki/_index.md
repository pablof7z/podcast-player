# Wiki Index

> Derived cache — do not hand-edit. Rebuilt by proactive-context after each capture.

Last updated: 2026-06-06

## episode-matching (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [episode-matching](episode-matching.md) | Episode Matching | The Rust kernel's `episode_enclosure_url` function performs a case-insensitive UUID comparison to correctly match iOS uppercase UUID strings with stored lowerca | capture | warm | 2026-06-04 | episode-matching |

## general (6 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [inbox-triage](inbox-triage.md) | Inbox Triage | Inbox triage sends all needy episodes in a single user message to the agent, not in chunked batches | capture | warm | 2026-06-04 | general |
| [rust-dylib-xcode-integration](rust-dylib-xcode-integration.md) | Rust Dylib Xcode Integration | The Rust dylib for the podcast module is retained (not deleted) with its install name fixed to `@rpath/libnmp_app_podcast.dylib` to avoid duplicate-symbol confl | capture | warm | 2026-06-04 | general |
| [concurrency-models](concurrency-models.md) | Concurrency Models | O(N×M) hashing is performed off the MainActor via `Task.detached` on the push path. | capture | warm | 2026-06-06 | general |
| [domain-consistency](domain-consistency.md) | Domain Consistency | The application avoids bidirectional-sync bugs by forbidding Swift-only domain state across projection passes. | capture | warm | 2026-06-06 | general |
| [ffi-transport](ffi-transport.md) | FFI Transport | The FFI transport uses FlatBuffers for the frame transport via `nmp_app_podcast_decode_update_frame`. | capture | warm | 2026-06-06 | general |
| [performance-profiling](performance-profiling.md) | Performance Profiling | To identify which layer dominates performance, reconcile, build, and profile the current hot path on an iOS simulator | capture | warm | 2026-06-06 | general |

## local-llm-service (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [local-llm-service](local-llm-service.md) | Local LLM Service | The `LocalLLMService` manages the lifecycle of the on-device engine by loading it when a local model is selected and ensures the engine is loaded via an idempot | capture | warm | 2026-06-05 | local-llm-service |

## model-download-management (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [model-download-management](model-download-management.md) | Model Download Management | Model downloads are routed through the same background `URLSession` infrastructure as episodes to ensure progress is maintained when the app is suspended or ter | capture | warm | 2026-06-05 | model-download-management |

## podcast-state-management (3 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [content-hashing](content-hashing.md) | Content Hashing | Content hashes (`libraryMetaHash`/`snapshotContentHash`) exclude volatile position and buffering data to prevent redundant list re-renders. | capture | warm | 2026-06-06 | podcast-state-management |
| [podcast-state-management](podcast-state-management.md) | Podcast State Management | The system distinguishes between durable state changes (such as completion or cancellation) and transient progress updates to optimize global library re-project | capture | warm | 2026-06-04 | podcast-state-management |
| [projection-optimization](projection-optimization.md) | Projection Optimization | Summary-level diffing ensures only modified episodes incur `toEpisode` projection costs. | capture | warm | 2026-06-06 | podcast-state-management |

