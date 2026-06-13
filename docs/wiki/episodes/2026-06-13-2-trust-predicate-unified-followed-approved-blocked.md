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
  - social-actions
  - nostr-conversations
supersedes:
  - 2026-06-13-3-kernel-owned-approvedpeerstore-with-unified-trust
related_claims: []
source_lines:
  - 8120-8217
  - 8226-8332
captured_at: 2026-06-13T03:49:37Z
---

# Episode: Trust predicate unified: (followed || approved) && !blocked

## Prior State

Trust was 100% follow-set based (ActiveFollowSet), with no manual approval path. ActiveFollowSet has no public mutation API — trust = followed, full stop. The iOS approval UI (nostrAllowedPubkeys/nostrBlockedPubkeys/nostrPendingApprovals) was fully orphaned scaffolding: nothing populated the pending queue, and allow/block sets gated nothing in the kernel or responder.

## Trigger

Design investigation for conversations completeness revealed that the follow-set is an upstream NMP crate with no approval API, and the Swift approval surface gates nothing — the planner's intuition that approval needed to become real was correct.

## Decision

Introduce a kernel-owned ApprovedPeerStore (allow+block hex pubkey sets, disk-persisted, per-account, atomic tmp-rename) composed with ActiveFollowSet in SocialState. The unified trust predicate is: trust(pubkey) = (followed(pubkey) OR approved(pubkey)) AND NOT blocked(pubkey). Block is an absolute override (even a followed pubkey, if explicitly blocked, is untrusted). Approved-but-unfollowed senders DO get auto-replied (approval is a stronger per-peer intent than a follow; the responder's turn-cap/wtd-end/dedup defenses bound the risk). Both the responder gate and the projection consume this single composed predicate.

## Consequences

- ActiveFollowSet stays untouched (upstream NMP crate, not forked); composition happens in SocialState
- Orphaned iOS approval scaffolding deleted: nostrPendingApprovals, NostrPendingApproval.swift, NostrApprovalPresenter.swift, PendingApprovalRow
- Four new SocialAction variants (ApprovePeer, BlockPeer, RemoveApproval, RemoveBlock) dispatched through the existing podcast.social action router
- ApprovedPeerStore is per-account durable (NOT cleared on account switch; reloaded from the new account's data_dir)
- New real-path tests drive the full handle_social_action → persist → infra.bump() → re-emit chain, with mutation-guard proof (removing bump causes test failure)
- No new wire field for v1 — trusted already exists on NostrConversationDTO, just changes value

## Open Tail

- Optional trust_source field on the DTO to distinguish why trusted (follow-up, not v1)
- Android Conversations UI still missing (decodes the payload but renders nothing)
- Flat agent_notes wire field retirement is a follow-up (AgentNotesView is NOT the inbound feed — it renders local Note/NoteKind)
- kind:0 profile hydration already rides resolved_profiles; claimProfile(counterpartyHex) on view-appear is a follow-up

## Evidence

- transcript lines 8120-8217
- transcript lines 8226-8332

