---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: architecture
status: superseded
subjects:
  - approved-peer-store
  - trust-predicate
  - social-state
  - agent-note-responder
supersedes:
  - 2026-06-13-4-unified-trust-predicate-followed-approved-blocked
related_claims: []
source_lines:
  - 8120-8216
  - 8232-8267
  - 8295-8318
  - 8326-8368
captured_at: 2026-06-13T03:37:30Z
---

# Episode: Kernel-owned ApprovedPeerStore with unified trust predicate (followed || approved) && !blocked

## Prior State

Trust in the Nostr conversation system was 100% follow-set based (ActiveFollowSet from NIP-02 kind:3 p-tags), with no manual-approval path. The Swift approval surface (nostrAllowedPubkeys/nostrBlockedPubkeys/nostrPendingApprovals) was orphaned scaffolding: no production call site populated the pending queue, and the allow/block sets gated nothing in the kernel responder or projection.

## Trigger

Design investigation found: (1) ActiveFollowSet has no public mutation API — trust is purely follow-set with no approval path; (2) the Swift approval state gates nothing in FFI dispatch or the kernel; (3) the planner's premise to 'retire AgentNotesView' was wrong — it renders local personal notes, not the agent_notes wire field.

## Decision

Introduce a kernel-owned, per-account, disk-persisted ApprovedPeerStore (allow-list + block-list of hex pubkeys) with 4 SocialAction variants (ApprovePeer, BlockPeer, RemoveApproval, RemoveBlock). Compose it with ActiveFollowSet into a unified trust predicate: trust(pubkey) = (followed(pubkey) || approved(pubkey)) && !blocked(pubkey), where block is an absolute override even over follows. Both the responder gate and the social projection consume the same composed predicate. Approved-but-unfollowed senders ARE auto-replied (approval is a stronger per-peer intent than follow, bounded by turn-cap/dedup/wtd-end defenses). Delete the orphaned nostrPendingApprovals/NostrPendingApproval/NostrApprovalPresenter from Swift.

## Consequences

- Real-path re-emit tests with mutation-guard proof: ApprovePeer dispatched through handle_social_action flips trusted=true on next tick; BlockPeer overrides a followed peer to trusted=false. Temporarily removing infra.bump() from the ApprovePeer arm causes the test to fail as expected.
- Fail-closed on poisoned mutex: both the trust_predicate and the responder gate return false/deny-all when the ApprovedPeerStore mutex is poisoned — a blocked+followed peer never becomes trusted through a crash hole.
- ApprovedPeerStore persists per-account under the bound data dir (not cleared on account switch, unlike session slots).
- ActiveFollowSet (upstream nmp-nip02) is NOT forked; composition happens in the app's SocialState.
- No new wire field in v1 — the existing trusted boolean on NostrConversationDTO flips value, not shape. trust_source field deferred to follow-up.
- Orphaned Swift approval scaffolding deleted: NostrPendingApproval.swift, NostrApprovalPresenter.swift, PendingApprovalRow removed; AgentAccessControlView simplified to Allowed/Blocked tabs.

## Open Tail

- Android Conversations UI (no UI exists yet; decoding already lands at DomainFrames.kt:142).
- kind:0 profile hydration rides existing resolved_profiles seam — add claimProfile(counterpartyHex) on view-appear as follow-up, don't duplicate into podcast.social.
- Flat agent_notes wire field + composite.agentNotes retirement when nothing reads it.
- Optional trust_source DTO field for distinguishing why a peer is trusted.

## Evidence

- transcript lines 8120-8216
- transcript lines 8232-8267
- transcript lines 8295-8318
- transcript lines 8326-8368

