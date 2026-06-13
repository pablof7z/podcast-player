---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: product
status: active
subjects:
  - social-trust-predicate
  - approved-peer-store
  - nostr-conversations
supersedes:
  - 2026-06-13-2-kernel-owned-approve-block-allow-list
related_claims: []
source_lines:
  - 8140-8197
  - 8232-8256
  - 8296-8318
  - 8329-8368
captured_at: 2026-06-13T04:09:51Z
---

# Episode: Kernel-owned approve/block allow-list drives Nostr conversation trust

## Prior State

Trust in Nostr conversations was computed solely from the NIP-02 follow set (ActiveFollowSet, an upstream crate with no manual-approval API). iOS carried an orphaned approval UI (allow/block/pending) that gated nothing in the kernel — nothing populated the pending queue and the allow-list was disconnected from the trust decision.

## Trigger

PR #423 landed a real Rust conversation projection whose `trusted` flag was derived only from the follow set, leaving no kernel mechanism for manual peer approval or blocking. The orphaned iOS approval scaffolding was identified as dead code contradicting the 'no scaffold' mandate.

## Decision

Introduced a kernel-owned `ApprovedPeerStore` (persisted allow+block hex sets under the account-scoped data dir) with a unified trust predicate `(followed || approved) && !blocked` that drives BOTH the social projection and the auto-responder gate. Block is an absolute kill-switch overriding follow. Fail-closed on poisoned mutex (denies all trust if the approved-store lock is poisoned). Four new `SocialAction` variants (ApprovePeer, BlockPeer, RemoveApproval, RemoveBlock) are dispatched through the existing `podcast.social` router arm, mutate the store, persist, and call `infra.bump()` at the real action site — never a test-only `fetch_add`. iOS approve/block UI rewired to dispatch kernel actions; orphaned `NostrPendingApproval`/`NostrApprovalPresenter`/pending-tab deleted.

## Consequences

- Approved peers get auto-replies even without a follow (approval is a stronger per-peer intent than following, bounded by turn-cap/wtd-end/dedup defenses).
- Approved peers persist per account data-dir — they must NOT be routed through `clear_for_account_switch` (which is for session slots).
- Action-path re-emit tests include mutation-guard proofs (removing `infra.bump()` causes the test to fail, confirming the guard works).
- The `ActiveFollowSet` upstream crate is NOT forked — composition happens in `SocialState`, preserving NMP-sync discipline.
- No new wire field in v1 (trusted verdict changes value, not shape), so no snake_case/golden churn. A future `trust_source` field is explicitly v2.
- Android and the flat `agent_notes` wire-field retirement are follow-ups, not v1.

## Open Tail

- Future `trust_source` DTO field to distinguish why a peer is trusted (followed vs approved).
- Android conversations UI to consume the same `podcast.social` frame.
- Retire the flat `agent_notes` wire field once nothing reads it.

## Evidence

- transcript lines 8140-8197
- transcript lines 8232-8256
- transcript lines 8296-8318
- transcript lines 8329-8368

