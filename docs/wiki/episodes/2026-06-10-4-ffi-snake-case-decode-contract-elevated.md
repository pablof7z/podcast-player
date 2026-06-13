---
type: episode-card
date: 2026-06-10
session: 38f8143c-c90d-49e3-a8fa-8d5ca17ac319
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/38f8143c-c90d-49e3-a8fa-8d5ca17ac319.jsonl
salience: architecture
status: superseded
subjects:
  - ffi-decode
  - snake-case-contract
  - kernel-bridge
supersedes:
  - 2026-06-10-1-embedded-widgetsnapshot-codingkeys-conflict-with-convertfromsnakecase
related_claims: []
source_lines:
  - 1370-1392
captured_at: 2026-06-12T13:48:00Z
---

# Episode: FFI snake_case decode contract elevated to project memory

## Prior State

No documented contract governing how Rust-emitted snake_case JSON maps to Swift Codable types through the bridge; individual developers added explicit CodingKeys to embedded types without understanding they conflict with convertFromSnakeCase

## Trigger

The WidgetSnapshot CodingKeys regression (PR #371) revealed that this was a systemic contract gap, not an isolated typo — any future embedded type added to PodcastUpdate would hit the same bug if its author followed the 'obvious' pattern of declaring CodingKeys

## Decision

Created memory file ffi_decode_snakecase_contract.md documenting the rule: Rust emits snake_case JSON via serde; the iOS KernelBridge decodes with .convertFromSnakeCase; embedded types must NOT declare explicit CodingKeys (HandoffState excepted as a non-embedded type on a separate decode path)

## Consequences

- Future embedded types added to PodcastUpdate will have an explicit doctrinal reference preventing the same CodingKeys mistake
- KernelDecoding.swift centralizes the decoder configuration, making the contract enforceable at a single point

## Open Tail

*(none)*

## Evidence

- transcript lines 1370-1392

