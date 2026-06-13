---
type: episode-card
date: 2026-06-06
session: deb49f4f-f275-419a-ab1c-b68c123af73b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/deb49f4f-f275-419a-ab1c-b68c123af73b.jsonl
salience: reversal
status: superseded
subjects:
  - delta-projection
  - ffi-transport
  - wire-contract
supersedes: []
related_claims: []
source_lines:
  - 2268-2275
captured_at: 2026-06-12T13:22:24Z
---

# Episode: Delta projection (Win B) rejected — not justified post-fix

## Prior State

Per-row/delta library projection (Win B) was under consideration to reduce FFI transport cost by sending only changed rows instead of the full library JSON on every rev bump.

## Trigger

Post-merge measurement on populated library showed that after the O(N²) fix + #264 (off-main decode) + #265 (rev-discipline), a durable-change rebuild is ~7.6 ms Rust-side and the decode runs off the MainActor — infrequent and non-UI-blocking.

## Decision

Skip the delta projection (Win B). The remaining transport cost (~3.8 MB off-main decode on infrequent durable changes) does not justify the D5 wire-contract risk and implementation complexity.

## Consequences

- No D5 wire-contract change needed; architecture stays simple
- Single-source-of-truth (Rust → JSON snapshot → Swift) model preserved
- Future perf work should be gated on empirical populated-library measurement, not empty-sim or synthetic numbers

## Open Tail

- If library sizes grow far beyond 3,600 episodes, reconsider delta transport with the measurement harness as a baseline.

## Evidence

- transcript lines 2268-2275

