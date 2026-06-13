---
type: episode-card
date: 2026-05-15
session: f3b466c6-7791-44b3-b004-aae2066a9019
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/f3b466c6-7791-44b3-b004-aae2066a9019.jsonl
salience: architecture
status: superseded
subjects:
  - secp256k1-dep-consolidation
  - p256k-module
supersedes:
  - 2026-05-15-3-duplicate-secp256k1-symbol-conflict-resolved-by
related_claims: []
source_lines:
  - 2631-2677
  - 2862-2869
  - 2897-2927
  - 2996-3096
  - 3119-3172
  - 3378-3406
  - 3447-3514
captured_at: 2026-06-12T12:39:29Z
---

# Episode: secp256k1 dependency consolidated to single fork, eliminating duplicate C symbols

## Prior State

Two forks of the same secp256k1 C library were resolving via SPM: GigaBitcoin/secp256k1.swift (used by Podcastr, exports module `P256K`) and 21-DOT-DEV/swift-secp256k1 (used by ios-shake-feedback, exports module `secp256k1`). Both compile the same C symbols, producing duplicate `_secp256k1_*` link errors. ios-shake-feedback had originally chosen 21-DOT-DEV to coexist with NDKSwift (which Podcastr no longer depends on).

## Trigger

Link failure with duplicate `_secp256k1_schnorrsig_sign32`, `_secp256k1_ec_pubkey_serialize`, etc. surfaced during fresh SPM resolve after Rust core integration.

## Decision

Unified both Podcastr and ios-shake-feedback onto GigaBitcoin/secp256k1.swift (which provides the `P256K` module). Changed ios-shake-feedback's Package.swift dependency and ShakeFeedbackCrypto.swift from `import secp256k1` to `import P256K`. git-init'd ios-shake-feedback to capture this change. NDKSwift removed from the dependency graph entirely.

## Consequences

- Single secp256k1 C library in the binary — no more duplicate-symbol link errors
- ios-shake-feedback now uses `P256K` module (same crypto, different Swift surface)
- 21-DOT-DEV/swift-secp256k1 is no longer a viable dependency for any project that also uses GigaBitcoin — they must choose one fork
- NDKSwift fully removed from Podcastr's dependency tree

## Open Tail

- ios-shake-feedback has no remote git repository yet — only local history exists

## Evidence

- transcript lines 2631-2677
- transcript lines 2862-2869
- transcript lines 2897-2927
- transcript lines 2996-3096
- transcript lines 3119-3172
- transcript lines 3378-3406
- transcript lines 3447-3514

