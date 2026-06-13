---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - trust-predicate
  - social-projection
  - approved-peer-store
  - conversations
supersedes: []
related_claims: []
source_lines:
  - 8120-8215
captured_at: 2026-06-13T02:56:17Z
---

# Episode: Unified trust predicate: (followed || approved) && !blocked

## Prior State

Trust in the conversation system was 100% derived from the NIP-02 follow set (ActiveFollowSet) — a user was trusted iff they appeared in the user's kind:3 p-tags. iOS had an approval UI (allow/block/pending) but it was fully orphaned: nothing populated the pending queue and the allow/block sets gated nothing in the kernel.

## Trigger

Design investigation for conversations completeness revealed: (1) ActiveFollowSet has no manual-approval API, (2) the Swift approval state is orphaned scaffolding with no producer and no kernel consumer, (3) AgentNotesView is the local personal notes UI — NOT the inbound Nostr feed (planner's 'retire AgentNotesView' premise was wrong).

## Decision

Introduce a kernel-owned, per-account, disk-persisted ApprovedPeerStore (allow+block hex pubkey sets) composed with ActiveFollowSet into a single unified trust predicate: trust(pubkey) = (followed(pubkey) OR approved(pubkey)) AND NOT blocked(pubkey). Block is an absolute override even over follows. The composition lives in SocialState, not in the upstream ActiveFollowSet crate. Four new SocialAction variants (ApprovePeer/BlockPeer/RemoveApproval/RemoveBlock) dispatch through the existing podcast.social action router. iOS allow/block buttons wired to kernel actions; orphaned nostrPendingApprovals/NostrApprovalPresenter deleted.

## Consequences

- An explicitly-approved-but-unfollowed sender IS auto-replied to — approval carries more intent than a follow, and the responder's turn-cap/wtd-end/dedup bounds the risk.
- Block overrides follow — a blocked pubkey gets no reply even if followed.
- ApprovedPeerStore is per-account durable (keyed by data_dir), NOT cleared on account switch (unlike session slots).
- No new wire field for v1 — approval changes the value of the existing trusted boolean, not the DTO shape. A trust_source field distinguishing followed vs approved is a follow-up.
- kind:0 profile hydration rides the existing resolved_profiles seam — do NOT duplicate into podcast.social.
- The #423 real-bump rule applies: approve/block actions MUST call state.social.infra.bump() at the real action site.

## Open Tail

- Android Conversations UI (no UI exists yet).
- Retire the flat agent_notes wire field + composite.agentNotes once nothing reads it.
- Optional trust_source DTO field for distinguishing why a peer is trusted.
- claimProfile(counterpartyHex) on view-appear for kind:0 hydration.

## Evidence

- transcript lines 8120-8215

