---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - swift-codegen
  - bridge-dto-maintenance
  - coding-keys-hazard
supersedes:
  - 2026-06-10-4-ffi-snake-case-decode-contract-elevated
related_claims: []
source_lines:
  - 5120-5164
  - 5179-5180
captured_at: 2026-06-12T15:07:20Z
---

# Episode: Swift bridge codegen structurally excludes #371 CodingKeys hazard

## Prior State

The `.generated.swift` bridge DTO files were hand-maintained, requiring manual synchronization with Rust source types. The #371 incident showed that explicit `CodingKeys` enums with snake_case raw values could silently drift from the Rust wire shape, causing frame drops.

## Trigger

The #403/#404 reviews confirmed that the 7 new domain-frame envelopes had no explicit CodingKeys (safe under `.convertFromSnakeCase`), but this was a manual property — future additions could reintroduce the hazard class.

## Decision

Hand-rolled emitter (`swift_codegen` bin) generates 7 of 8 bridge DTOs from Rust source field manifests. The emitter structurally never emits explicit snake_case `CodingKeys` — all Swift fields are camelCase and `.convertFromSnakeCase` handles the Rust↔Swift key mapping automatically. A CI drift gate (`swift-bridge-codegen-drift` job) fails the build if Generated/ files drift from regenerated output. `PodcastSettingsSnapshot` is left hand-maintained (mixed CodingKeys with per-field key overrides) and tracked as a follow-up.

## Consequences

- The #371 stale-mirror hazard class is structurally impossible for 7/8 bridge DTOs
- Zero-diff faithfulness proof: generated files are byte-identical to checked-in originals, so wire shapes are unchanged
- Adding new Rust fields to any of the 7 covered types automatically flows to Swift on next codegen run; drift gate catches any hand-edit divergence
- SettingsSnapshot remains a manual maintenance point, tracked in BACKLOG.md

## Open Tail

- swift-codegen-settings-snapshot follow-up: extend the emitter field manifest to model per-field CodingKeys key overrides, eliminating the last hand-maintained bridge DTO

## Evidence

- transcript lines 5120-5164
- transcript lines 5179-5180

