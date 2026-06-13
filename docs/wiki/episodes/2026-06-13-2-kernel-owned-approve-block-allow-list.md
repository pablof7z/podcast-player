---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - trust-predicate
  - approved-peer-store
  - nostr-social
  - auto-responder
supersedes:
  - 2026-06-13-2-trust-predicate-unified-followed-approved-blocked
  - 2026-06-13-3-fail-closed-on-poisoned-approved-store
related_claims: []
source_lines:
  - 8120-8217
  - 8228-8330
  - 8332-8370
captured_at: 2026-06-13T03:58:09Z
---

# Episode: Kernel-owned approve/block allow-list drives Nostr trust with fail-closed guarantee

## Prior State

Trust was determined solely by ActiveFollowSet (NIP-02 kind:3 p-tags), an upstream crate with no public mutation API. The only trust gate was fs.predicate(): a pubkey is trusted if and only if it appears in the active account's follow set. Meanwhile, iOS carried fully orphaned approval scaffolding — nostrAllowedPubkeys/nostrBlockedPubkeys/nostrPendingApprovals — that had no producer for the pending queue and no effect on the kernel's trust decision.

## Trigger

PR #423 landed a real Rust conversation projection whose trusted flag was computed from the follow set alone. Investigation confirmed: (1) ActiveFollowSet has no approval API, (2) iOS approval UI is completely disconnected from the kernel, (3) both the responder gate and the projection consume the same single-source predicate.

## Decision

Introduce a kernel-owned, per-account, disk-persisted ApprovedPeerStore (BTreeSet allow-list + block-list of hex pubkeys) composed with ActiveFollowSet in SocialState. The unified trust predicate is: trust(pubkey) = (followed(pubkey) OR approved(pubkey)) AND NOT blocked(pubkey). Block is an absolute override — even a followed+blocked peer is untrusted. On poisoned mutex, the predicate fails CLOSED (denies all trust, blocks all auto-reply). The orphaned Swift approval scaffolding (nostrPendingApprovals, NostrPendingApproval, NostrApprovalPresenter, PendingApprovalRow) is deleted. ActiveFollowSet is NOT forked (upstream NMP crate); composition happens in the app's SocialState.

## Consequences

- Approval is now a real, kernel-enforced gate: an explicitly-approved sender IS auto-replied to (approval is a stronger per-peer intent than a bulk follow)
- Block is an absolute kill-switch that overrides follow — a followed+blocked pubkey gets no auto-reply
- Responder turn-cap (MAX_OUTGOING_TURNS_PER_ROOT=10), wtd-end gate, and dedup still bound blast radius independently of trust source
- Fail-closed on poisoned mutex: both the trust_predicate() closure and the responder gate deny all trust rather than dropping the blocklist
- Action-path re-emit tests with mutation-guard proof: dispatching ApprovePeer/BlockPeer through the real handle_social_action seam (not direct calls or manual fetch_add) proves the domain re-emits with trusted flipped
- ApprovedPeerStore is per-account durable (keyed by data dir), NOT cleared on account switch (unlike session slots)
- iOS approve/block buttons now dispatch podcast.social kernel actions; the kernel is the source of truth

## Open Tail

- Optional trust_source field on NostrConversationDTO (to distinguish followed vs approved) — deferred from v1
- Android Conversations UI to consume the already-decoded podcast.social frame
- Flat agent_notes wire field retirement (no UI binds it meaningfully now that conversations exist)
- Resolved_profiles seam for kind:0 profile hydration (claimProfile on view-appear, not duplicated in podcast.social)

## Evidence

- transcript lines 8120-8217
- transcript lines 8228-8330
- transcript lines 8332-8370

