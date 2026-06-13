---
type: episode-card
date: 2026-06-03
session: c43d5e77-d667-4e71-a574-47aaab5b6a7a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c43d5e77-d667-4e71-a574-47aaab5b6a7a.jsonl
salience: architecture
status: active
subjects:
  - swift-to-kernel-signing-migration
  - nmp-kernel-signing
  - nip46-removal
  - nostrkeypair-deletion
supersedes: []
related_claims: []
source_lines:
  - 8033-8072
  - 8184-8216
  - 8260-8270
  - 8315-8360
  - 8594-8742
captured_at: 2026-06-12T13:02:09Z
---

# Episode: All Nostr signing/crypto removed from Swift — kernel owns keys

## Prior State

Swift app directly performed Nostr signing using local crypto: NostrKeyPair/secp256k1, LocalKeySigner, Nip46/ stack (RemoteSigner, Nip44, ChaCha20, schnorr), and a WebSocket relay client for NIP-42 auth. App-Rust also signed events independently via host_op_publish::sign_event and blossom.rs::build_auth_event. NMP was pinned at v0.2.2 without make_active or sign-for-return APIs.

## Trigger

Clean-architecture goal requiring 'no logic that belongs in Rust exists in Swift' — combined with NMP v0.2.4 shipping make_active (for non-active account registration) and nmp_app_sign_event_for_return (for Blossom sign-and-return), making kernel-owned signing feasible.

## Decision

All Nostr signing, key material, and crypto deleted from Swift (Nip46/, NostrKeyPair, LocalKeySigner, RemoteSigner, WebSocket relay). NMP v0.2.4 pin adopted. Swift dispatches only semantic data through the kernel. UserIdentityStore rearchitected to mirror kernel's activeAccount projection. NMP is now the sole signing authority for active-account operations.

## Consequences

- Nip46/ directory, NostrKeyPair.swift, and all Swift crypto (schnorr, P256K, ChaCha20, Nip44) deleted — grep gate structurally empty
- NMP pin bumped from v0.2.2 (rev 6a0c4fd) to v0.2.4 (rev f0b5012), breaking make_active arity on create_new_account/signin_nsec/signin_bunker call sites
- Avatar, agent-artwork, and shake-feedback Blossom uploads degraded (throw 'unavailable') — not fake-signed
- app-Rust host_op_publish.rs and blossom.rs still contain nostr-crate signing for per-podcast NIP-F4 and Blossom auth (deferred to PR #246)
- PR #248 landed on main (0c590b26), certified in isolated worktree: 981 tests pass, iOS sim build green

## Open Tail

- PR #246 (D13 sign-and-return) will wire the remaining app-Rust signing through kernel, restoring degraded uploads
- NostrSigner protocol/signer property on UserIdentityStore is dead code waiting for final cleanup

## Evidence

- transcript lines 8033-8072
- transcript lines 8184-8216
- transcript lines 8260-8270
- transcript lines 8315-8360
- transcript lines 8594-8742

