---
type: episode-card
date: 2026-05-17
session: 8e07824e-448c-4122-8a44-23c34c83b826
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8e07824e-448c-4122-8a44-23c34c83b826.jsonl
salience: architecture
status: active
subjects:
  - swift-secp256k1-version-conflict
  - ios-shake-feedback
  - p256k-to-secp256k1-migration
supersedes:
  - 2026-05-15-3-secp256k1-dependency-consolidated-to-single-fork
related_claims: []
source_lines:
  - 90-97
  - 273-285
  - 394-496
  - 621-628
captured_at: 2026-06-12T12:40:09Z
---

# Episode: ios-shake-feedback ported from P256K to secp256k1 module to resolve transitive dependency conflict

## Prior State

ios-shake-feedback was written against swift-secp256k1 0.20+, importing the P256K module and using P256K.Schnorr.PrivateKey. The workspace had swift-secp256k1 pinned at 0.19.0 (via NDKSwift's constraint), which only exports secp256k1 and zkp products — no P256K. swift-secp256k1 0.23.x dropped the secp256k1 product entirely, renaming to P256K/libsecp256k1, making the two consumers (NDKSwift and ios-shake-feedback) require incompatible versions of the same package.

## Trigger

Build failed with 'product P256K required by package ios-shake-feedback not found in package swift-secp256k1' and 'Package ios-shake-feedback enables traits on swift-secp256k1 that declares no traits'. NDKSwift requires from: 0.19.0 (pinned), while ios-shake-feedback also requires from: 0.19.0 but needs APIs only in 0.20+.

## Decision

Ported ios-shake-feedback's ShakeFeedbackCrypto.swift from import P256K / P256K.Schnorr.PrivateKey to import secp256k1 / secp256k1.Schnorr.PrivateKey (the 0.19.0 API namespace). The underlying crypto API is identical; only the module and type namespace differ. Updated Package.swift dependency to remain at from: 0.19.0, ensuring both NDKSwift and ios-shake-feedback resolve to the same pinned version.

## Consequences

- Both packages now share swift-secp256k1 0.19.0, eliminating duplicate C symbol linkage risk for secp256k1 functions
- ios-shake-feedback is now coupled to the 0.19.0 secp256k1 module API — future upgrades to 0.20+ would require re-porting to P256K namespace or a compatibility shim
- The swift-secp256k1 library made a breaking product rename between 0.19.0 and 0.20.0 (secp256k1→P256K, zkp→ZKP) — any new package adding this dependency must use the correct namespace for the resolved version

## Open Tail

- If NDKSwift upgrades its swift-secp256k1 dependency past 0.20.0, ios-shake-feedback would need to be ported back to P256K or a version-conditional wrapper introduced
- GigaBitcoin/secp256k1.swift (the 0.23.1 pin in ios-shake-feedback's own Package.resolved) is a different fork than 21-DOT-DEV/swift-secp256k1 — the comment in ios-shake-feedback's Package.swift claims they're forks of each other with same crypto but different Swift module surfaces

## Evidence

- transcript lines 90-97
- transcript lines 273-285
- transcript lines 394-496
- transcript lines 621-628

