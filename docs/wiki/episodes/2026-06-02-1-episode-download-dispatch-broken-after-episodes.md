---
type: episode-card
date: 2026-06-02
session: e1cfd663-230d-4f78-9078-0c9ed8b6a4bb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/e1cfd663-230d-4f78-9078-0c9ed8b6a4bb.jsonl
salience: root-cause
status: active
subjects:
  - download-dispatch
  - episode-lookup
  - pr-227-regression
supersedes:
  - 2026-05-26-2-episodes-isolated-from-monolithic-appstate-into
related_claims: []
source_lines:
  - 1353-1375
  - 1662-1675
captured_at: 2026-06-12T12:55:10Z
---

# Episode: Episode download dispatch broken after episodes moved out of state

## Prior State

`kernelDownload(_ id:)` looked up episodes via `state.episodes.first(where: { $0.id == id })`, which worked when episodes lived inside the `state` struct

## Trigger

PR #227 moved `episodes` out of `state` into a top-level `@Observable` property on `AppStateStore`, making `state.episodes` always empty — so the guard always failed and downloads silently returned with an error log

## Decision

Replace `state.episodes.first(where:)` with the canonical `episode(id:)` accessor that reads from `self.episodes` (the correct property)

## Consequences

- Downloads dispatch correctly again — episode URL is found and passed to Rust
- Any future code touching episodes must use `episode(id:)` or `self.episodes`, never `state.episodes`
- The `state` struct is no longer the source-of-truth for episodes; `AppStateStore` itself is

## Open Tail

*(none)*

## Evidence

- transcript lines 1353-1375
- transcript lines 1662-1675

