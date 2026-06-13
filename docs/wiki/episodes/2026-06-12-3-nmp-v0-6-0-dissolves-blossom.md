---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - nmp-v0.6-adoption
  - blossom-upload
  - social-graph-reactive
supersedes:
  - 2026-05-13-3-transcript-payload-size-exceeds-relay-limits
  - 2026-05-13-1-photo-upload-via-blossom-deferred-feature
related_claims: []
source_lines:
  - 6048-6108
captured_at: 2026-06-12T21:53:41Z
---

# Episode: NMP v0.6.0 dissolves Blossom and social-graph blockers — adopt upstream instead of building new

## Prior State

BACKLOG planned building a net-new async sign-and-return capability for Blossom uploads, and building a reactive social-graph store from scratch for the trust gate and conversations

## Trigger

NMP v0.6.0 (#414, landed 2 days before this session) shipped nmp-blossom (typed nmp.blossom.upload action with full Build→Sign→Transport pipeline, working for both local nsec and NIP-46 bunker) and nmp-nip02 (follow/unfollow actions + reactive FollowListProjection + ActiveFollowSet trust predicate)

## Decision

Both workstreams shift from 'build new' to 'adopt upstream + delete hand-rolled code': (1) Blossom uploads route through nmp.blossom.upload, deleting BlossomUploader.swift; (2) Social handler replaces the one-shot 8s-timeout hardcoded-relay pull with the reactive FollowListProjection, wiring ActiveFollowSet → AgentNoteSummary.trusted (the declared blocker for agent-to-agent LLM responder). Conversations deliberately deferred to next cycle.

## Consequences

- Dramatically reduces scope/complexity of both workstreams — no new kernel signing capability needed
- BlossomUploader.swift becomes the last Swift upload transport to delete
- AgentNoteSummary.trusted (currently hardcoded false) becomes reactive to follow-state, unblocking the agent responder
- The identity-work conflict that blocked Blossom last cycle has cleared on the Rust side

## Open Tail

- ffi/snapshot.rs has in-flight uncommitted FFI-split work in the shared root — merge-time conflict risk flagged
- Conversations (grouping agent_notes by root_event_id into NostrConversation) explicitly deferred to next cycle

## Evidence

- transcript lines 6048-6108

