---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - swift-bridge-codegen
  - dto-boundary
  - codingkeys-hazard
supersedes:
  - 2026-06-12-6-swift-bridge-codegen-structurally-excludes-371
related_claims: []
source_lines:
  - 5115-5207
captured_at: 2026-06-12T15:48:16Z
---

# Episode: Hand-rolled Swift codegen replaces hand-maintained DTO mirrors

## Prior State

7 of 8 Generated/ Swift DTO files were hand-maintained mirrors of Rust types. One wrong CodingKey mapping (bug #371) froze the entire UI — a recurring failure class with no structural prevention. Adding new DTO fields required manual mirroring prone to drift and omission.

## Trigger

The #371 freeze incident demonstrated the stale-mirror hazard class. The per-domain transport work (cycle 4) required new DTO fields needing manual mirroring, re-exposing the risk. The codegen approach was deferred during cycle 4 as item D and prioritized in cycle 5.

## Decision

Adopted a hand-rolled Swift code generator (not schemars) that structurally excludes explicit snake_case CodingKeys from generated types — all Swift fields are camelCase with .convertFromSnakeCase handling the Rust↔Swift key mapping automatically. A CI drift gate (swift-bridge-codegen-drift job) fails the build if any generated file diverges from the checked-in version. PodcastSettingsSnapshot left as a follow-up because its mixed CodingKeys enum (~15 snake_case overrides) requires per-field override support not yet modeled in the generator.

## Consequences

- 7/8 bridge DTOs are now machine-generated with a zero-diff faithfulness proof (byte-identical to previous hand-maintained versions)
- The #371 stale-mirror hazard class is structurally closed for generated types — the generator cannot emit explicit snake_case CodingKeys
- CI drift gate catches any divergence between generated and checked-in files, preventing silent drift
- SettingsSnapshot generation tracked as swift-codegen-settings-snapshot follow-up in BACKLOG.md
- Hand-rolled emitter chosen over schemars to avoid adding derive-macro dependencies to the main crate and because custom decode logic (property wrappers, decodeIfPresent) cannot be reproduced by schema→Swift transforms

## Open Tail

- PodcastSettingsSnapshot generation (requires per-field CodingKeys override support in the generator manifest)
- Android wire-fixture test parity (iOS has KernelBridgeWireTests, Android now has DomainFrameWireTest)

## Evidence

- transcript lines 5115-5207

