---
type: episode-card
date: 2026-05-13
session: 9f3b9a0a-d40b-4658-ad51-c157a7780612
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f3b9a0a-d40b-4658-ad51-c157a7780612.jsonl
salience: architecture
status: active
subjects:
  - nostr-relay-routing
  - allowlist-gate
  - pending-friend-message
supersedes: []
related_claims: []
source_lines:
  - 2150-2155
captured_at: 2026-06-12T12:19:54Z
---

# Episode: Pending message registry authorizes allowlist bypass for delegation replies

## Prior State

Nostr inbound messages from pubkeys not in nostrAllowedPubkeys were always rejected at the relay service allowlist gate

## Trigger

Friend agents are not in the allowlist, so their replies would be dropped before reaching the agent responder

## Decision

NostrRelayService checks pendingFriendMessages BEFORE the allowlist gate; a pending entry itself is the authorization to route the inbound event directly to the agent responder

## Consequences

- Any outbound send_friend_message implicitly authorizes the friend's reply to bypass the allowlist
- The pending message registry becomes a source-of-truth for delegated inbound routing

## Open Tail

*(none)*

## Evidence

- transcript lines 2150-2155

