---
type: episode-card
date: 2026-05-28
session: 1a2f2460-74e7-4309-9dcc-99d19936c123
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/1a2f2460-74e7-4309-9dcc-99d19936c123.jsonl
salience: root-cause
status: active
subjects:
  - podcast-tui
  - snapshot-format
  - deserialization
supersedes:
  - 2026-05-28-1-tui-snapshot-delivery-replace-flatbuffers-json
related_claims: []
source_lines:
  - 1898-1904
captured_at: 2026-06-12T12:51:43Z
---

# Episode: TUI snapshot deserialization bypasses domain types

## Prior State

TUI tried to deserialize kernel snapshot JSON into podcast-core::EpisodeSummary, which required fields (pub_date, position_secs, download_state) absent from the wire format — causing every episode to silently fail to parse, leaving library/queue/search always empty

## Trigger

Debugging empty lists revealed that serde deserialization into domain structs failed silently because the FFI projection wire format omits fields the domain struct marks as required

## Decision

Replaced serde deserialization into domain types with raw JSON field extraction into TUI-local PodcastRow / EpisodeRow structs that use Option for every field and default gracefully on missing data

## Consequences

- TUI is decoupled from podcast-core domain type schema changes — the projection wire format is the contract, not the Rust struct
- TUI must maintain its own field extraction logic (parse_podcast_row, parse_episode_row, etc.) rather than sharing domain types
- Future snapshot format changes only require updating extraction functions, not re-aligning domain type derives

## Open Tail

- TUI-local row types could drift from kernel projections if not kept in sync manually

## Evidence

- transcript lines 1898-1904

