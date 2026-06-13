---
type: episode-card
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - nmp-blossom
  - nmp-nip02
  - blossom-upload
  - social-graph
  - v0.6.0-upstream
supersedes:
  - 2026-06-12-3-nmp-v0-6-0-dissolves-blossom
related_claims: []
source_lines:
  - 6049-6109
  - 6110-6145
captured_at: 2026-06-12T22:05:45Z
---

# Episode: NMP v0.6.0 dissolves Blossom and social-graph blockers — adopt-and-delete replaces build-new

## Prior State

Blossom uploads required building a net-new async sign-and-return capability (ADR-0043 design in BACKLOG). Social graph required building a one-shot follow-list fetch against hardcoded relay. Both were blocked by in-flight identity work in the shared root.

## Trigger

NMP v0.6.0 bump (#414, merged 2 days prior) shipped `nmp-blossom` (typed `nmp.blossom.upload` action with full Build→Sign→Transport pipeline, supporting both local nsec and NIP-46 bunker) and `nmp-nip02` (follow/unfollow actions + reactive `FollowListProjection` + `ActiveFollowSet` trust predicate).

## Decision

Both headliners shift from "build net-new capability" to "adopt upstream + delete hand-rolled code." Blossom: route avatar/artwork through `nmp.blossom.upload`, delete `BlossomUploader.swift` + app-Rust `blossom.rs`. Social graph: replace one-shot 8s pull with reactive `FollowListProjection`, wire `ActiveFollowSet` → `AgentNoteSummary.trusted` (unblocking agent responder and conversations).

## Consequences

- Blossom work scope drops from M-L to M (upstream ate the hard half)
- Social graph is no longer upstream-blocked — kind:3 store maturity arrived in v0.6.0
- Both items become adoption-and-deletion work rather than new-capability builds
- Identity-work conflict on the Rust side has cleared (only Android keypair gen remains in-flight)
- Cycle-7 dispatched three parallel tracks: Blossom adopt+delete, social graph reactive+trust gate, Android chapters+auto-skip rails

## Open Tail

- Blossom and social-graph implementations dispatched but not yet landed
- Conversations (grouping agent_notes by root_event_id into NostrConversation-shaped projection) explicitly deferred to next cycle

## Evidence

- transcript lines 6049-6109
- transcript lines 6110-6145

