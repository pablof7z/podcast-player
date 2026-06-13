---
type: episode-card
date: 2026-05-12
session: 514d3552-fbf6-4382-9488-8ba8b4289797
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/514d3552-fbf6-4382-9488-8ba8b4289797.jsonl
salience: root-cause
status: superseded
subjects:
  - agent-relay-bridge
  - peer-context
  - nostr-agent-responder
supersedes: []
related_claims: []
source_lines:
  - 1645-1659
captured_at: 2026-06-12T12:01:00Z
---

# Episode: Nostr peerContext Threading Bug Fix

## Prior State

AgentRelayBridge dispatched agent tools without setting `peerContext` on `PodcastAgentToolDeps`, even for Nostr-originated turns. This meant Nostr-triggered generation had no conversation metadata — a pre-existing bug that made it impossible to trace a podcast back to its originating Nostr thread.

## Trigger

While implementing generation-source provenance, discovered that `deps.peerContext` was always `nil` in `generateTTSEpisodeTool` because `AgentRelayBridge.runTurnLoop` never called `withPeerContext()` before dispatching tools.

## Decision

Added `rootEventID: String?` and `inboundEventID: String?` parameters to `AgentRelayBridge.reply(messages:peerPubkey:rootEventID:inboundEventID:)`. Inside the bridge, a `PeerConversationContext` is now constructed from those params and injected via `deps.withPeerContext(...)` before the tool dispatch loop. `NostrAgentResponder.process` now passes the `rootID` and `inbound.eventID` through to the bridge.

## Consequences

- Nostr-triggered podcast generation now correctly stamps `.nostr(rootEventID:peerPubkeyHex:)` on the resulting episode
- Any future Nostr-triggered tool call has access to peer conversation context
- `AgentRelayBridge.reply` signature changed — all call sites must supply the new parameters

## Open Tail

*(none)*

## Evidence

- transcript lines 1645-1659

