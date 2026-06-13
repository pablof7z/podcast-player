---
type: episode-card
date: 2026-05-15
session: 8c3708b9-22f2-404d-8534-c476e0cfcf75
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8c3708b9-22f2-404d-8534-c476e0cfcf75.jsonl
salience: architecture
status: superseded
subjects:
  - secp256k1-conflict
  - ios-shake-feedback
  - dependency-alignment
supersedes: []
related_claims: []
source_lines:
  - 3073-3114
  - 3135-3166
captured_at: 2026-06-12T12:37:22Z
---

# Episode: Duplicate secp256k1 symbol conflict resolved by aligning dependency

## Prior State

ios-shake-feedback depended on GigaBitcoin/secp256k1.swift. During the session, someone reverted its Package.swift back to GigaBitcoin with a comment saying Podcastr no longer depends on NDKSwift.

## Trigger

Linker failure on ndkswift branch: duplicate secp256k1 symbols — GigaBitcoin/secp256k1.swift 0.23.1 (transitive via ShakeFeedbackKit) and 21-DOT-DEV/swift-secp256k1 0.19.0 (transitive via NDKSwift). The relay-agent verified this exists on ndkswift HEAD itself, not from their migration.

## Decision

Re-applied the 21-DOT-DEV/swift-secp256k1 dependency switch in ios-shake-feedback's Package.swift and updated ShakeFeedbackCrypto.swift accordingly, so both NDKSwift and ShakeFeedbackKit use the same secp256k1 fork.

## Consequences

- Duplicate symbol linker error resolved
- ios-shake-feedback Package.swift comment now correctly reflects that Podcastr does depend on NDKSwift (via the ndkswift branch)
- Any future revert of this switch will reintroduce the linker failure

## Open Tail

- Monitor for NDKSwift or ShakeFeedbackKit updating their secp256k1 dependency — may need to re-align

## Evidence

- transcript lines 3073-3114
- transcript lines 3135-3166

