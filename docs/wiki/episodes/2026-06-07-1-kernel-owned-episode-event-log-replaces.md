---
type: episode-card
date: 2026-06-07
session: 9833dc25-72f9-4d4f-98d9-df476ead3e6d
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9833dc25-72f9-4d4f-98d9-df476ead3e6d.jsonl
salience: product
status: active
subjects:
  - episode-events
  - diagnostics-view
  - episode-audit-log
supersedes: []
related_claims: []
source_lines:
  - 38-57
  - 2092-2094
  - 2343-2357
  - 2421-2432
captured_at: 2026-06-12T13:27:03Z
---

# Episode: Kernel-owned episode event log replaces empty Swift-only audit store

## Prior State

Swift EpisodeAuditLogStore defined ~20 event kinds but only ever emitted one; the Rust kernel where real download/transcript/chapters work happens had zero event concept. Diagnostics view was always empty.

## Trigger

User reported that episode diagnostics never show any events, and that no pipeline stage tracks its activity.

## Decision

Created kernel-owned EpisodeEvent type with capped per-episode JSON persistence (episode-events/<id>.json, off the snapshot/persist hot path). Added lazy FFI getter nmp_app_podcast_episode_events. Instrumented every kernel pipeline stage (download requested/started/finished/failed, transcript attempt/ready/failed, chapters.ready, ads.ready). Deleted the redundant Swift-only EpisodeAuditLogStore.

## Consequences

- Diagnostics view now populates with real events from every pipeline stage
- Event persistence is independent of podcasts.json snapshot performance
- Canonical lowercase episode IDs unify correctly with Swift's uppercase uuidString file paths
- Swift EpisodeAuditLogView reads kernel events via FFI instead of maintaining its own store

## Open Tail

- AI chapters persisted only in Swift state (not kernel); chapters.ready only emitted for RSS and kernel-AI chapter paths, not Swift-compiled chapters

## Evidence

- transcript lines 38-57
- transcript lines 2092-2094
- transcript lines 2343-2357
- transcript lines 2421-2432

