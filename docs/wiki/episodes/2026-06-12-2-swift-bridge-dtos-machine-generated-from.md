---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: active
subjects:
  - swift-codegen
  - bridge-dto-source-of-truth
  - codegen-drift-gate
supersedes:
  - 2026-06-12-2-hand-rolled-swift-codegen-replaces-hand
related_claims: []
source_lines:
  - 5115-5180
  - 5528-5545
captured_at: 2026-06-12T17:50:10Z
---

# Episode: Swift bridge DTOs machine-generated from Rust source with CI drift gate

## Prior State

Eight .generated.swift files were hand-maintained mirrors of Rust DTO types, creating the #371 stale-mirror hazard class: a single wrong CodingKey could freeze the entire UI. The files drifted from their Rust sources over time with no CI enforcement.

## Trigger

The #371 regression (wrong CodingKey froze UI) demonstrated that hand-maintained bridge mirrors are a recurring failure mode. The initial codegen (#407) covered 7 of 8 files but left PodcastSettingsSnapshot hand-maintained due to its mixed CodingKeys enum with ~15 per-field snake_case overrides.

## Decision

A hand-rolled emitter (not schemars — avoids adding derive-macro deps and can reproduce custom decode logic) generates all 8 bridge files from Rust source types. CI drift gate (swift-bridge-codegen-drift job) runs the generator and fails on any diff. The emitter structurally never emits explicit snake_case CodingKeys for generated types (.convertFromSnakeCase handles the mapping). PodcastSettingsSnapshot is now fully generated including its ~15 explicit CodingKey overrides (field manifest carries coding_key_override).

## Consequences

- The #371 stale-mirror hazard class is structurally closed for the entire Rust→Swift DTO boundary
- Zero-diff faithfulness proof: all 8 generated files are byte-identical to their prior hand-maintained versions
- Future Rust DTO changes auto-propagate to Swift; CI catches any drift
- SettingsSnapshot's ~15 explicit raw-snake_case CodingKeys are preserved byte-identically — they intentionally do NOT decode under .convertFromSnakeCase (pre-existing quirk, documented, unchanged)
- No schemars dependency added to the main crate; generator is std-only (compiles in seconds)

## Open Tail

- swift-codegen-settings-snapshot follow-up tracked in BACKLOG (the generator now handles it, but the CodingKey override quirk under .convertFromSnakeCase deserves a separate investigation)

## Evidence

- transcript lines 5115-5180
- transcript lines 5528-5545

