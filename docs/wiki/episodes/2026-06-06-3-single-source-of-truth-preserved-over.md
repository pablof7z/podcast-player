---
type: episode-card
date: 2026-06-06
session: deb49f4f-f275-419a-ab1c-b68c123af73b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/deb49f4f-f275-419a-ab1c-b68c123af73b.jsonl
salience: architecture
status: active
subjects:
  - ffi-bridge
  - single-source-of-truth
  - kernel-model
  - swift-state
supersedes:
  - 2026-06-03-2-architecture-doctrine-domain-model-as-single
related_claims: []
source_lines:
  - 1-1
  - 137-152
captured_at: 2026-06-12T13:22:24Z
---

# Episode: Single source of truth preserved over Swift-side state duplication

## Prior State

User asked whether duplicating app state on the Swift side (so the FFI bridge only sends deltas) would pay off, even at the cost of losing single source of truth.

## Trigger

Investigation revealed that Swift already has KernelModel as an @Observable mirror of the Rust snapshot; the perceived slowness was caused by the O(N²) rebuild and full-library decode on the main thread, not by the FFI transport architecture itself.

## Decision

Keep Rust as the single source of truth. The KernelModel Swift-side mirror is already the delta consumer (content-hash-gated observation). The real bottleneck was quadratic rebuild cost and main-thread decode, both now fixed without introducing a second source of truth.

## Consequences

- No dual-state synchronization complexity or stale-state risk
- KernelModel remains a thin shell with no business logic or derived caches (D2, D4, D8 invariants preserved)
- Future FFI perf improvements should target the Rust-side build cost, not the transport shape

## Open Tail

*(none)*

## Evidence

- transcript lines 1-1
- transcript lines 137-152

