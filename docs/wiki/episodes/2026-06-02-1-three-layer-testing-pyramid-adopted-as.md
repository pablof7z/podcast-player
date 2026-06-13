---
type: episode-card
date: 2026-06-02
session: a6320d4d-f2c8-4a8b-a21a-d71f5af73509
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a6320d4d-f2c8-4a8b-a21a-d71f5af73509.jsonl
salience: architecture
status: active
subjects:
  - testing-pyramid
  - kernel-validation
  - maestro-ui-testing
supersedes: []
related_claims: []
source_lines:
  - 402-447
captured_at: 2026-06-12T12:58:50Z
---

# Episode: Three-layer testing pyramid adopted as architecture doctrine

## Prior State

No explicit strategy for validating kernel correctness vs. bridge fidelity vs. UI rendering; test scenarios existed only as a JSON specification file with no implementation guidance.

## Trigger

User asked how to structure testing to verify kernel-level behavior and overall app correctness, prompting analysis of existing test infrastructure and the Rust kernel bridge architecture.

## Decision

Adopted a 3-layer pyramid: (1) Rust `cargo test` for kernel unit correctness, (2) `podcast-tui` headless integration binary for bridge/FFI validation, (3) Maestro UI flows for user-journey rendering — each layer tests a different guarantee and no single tool covers all three. Kernel state assertions from Maestro require surfacing data into the accessibility tree via a debug snapshot dump.

## Consequences

- Four parallel PRs were structured around this pyramid: #234 (layer 1), #232 (layer 2), #235 + #233 (layer 3)
- Maestro flows can only assert what is surfaced via accessibilityIdentifier — in-process KernelModel state is unreachable from a separate process
- The podcast-tui integration binary becomes the canonical 'did the kernel actually fire' harness
- Future test additions should map to the appropriate layer rather than duplicating coverage

## Open Tail

- Debug snapshot dump view with stable accessibility ID not yet implemented — needed for Maestro kernel asserts on downloads, Nostr relay events, etc.
- Layer 2 (TUI integration) currently tests against live TWiT.tv RSS feed; a local fixture server would improve hermeticity

## Evidence

- transcript lines 402-447

