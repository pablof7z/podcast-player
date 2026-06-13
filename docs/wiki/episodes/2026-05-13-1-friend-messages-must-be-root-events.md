---
type: episode-card
date: 2026-05-13
session: 9f3b9a0a-d40b-4658-ad51-c157a7780612
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/9f3b9a0a-d40b-4658-ad51-c157a7780612.jsonl
salience: root-cause
status: active
subjects:
  - nostr-nip10-etag
  - send-friend-message
  - peer-event-publishing
supersedes:
  - 2026-05-12-2-nostr-peercontext-threading-bug-fix
related_claims: []
source_lines:
  - 2080-2098
captured_at: 2026-06-12T12:19:54Z
---

# Episode: Friend messages must be root events, not replies

## Prior State

publishFriendMessage added e-tags from peerContext, making the outbound message a threaded reply rather than a root event

## Trigger

Bug report: friend agent's reply was not detected by NIP-10 root lookup because the original send_friend_message was published with e-tags, making it a reply instead of a root event

## Decision

Friend messages are always published as root events with no e-tags; the e-tag logic was removed entirely from publishFriendMessage

## Consequences

- Friend agent replies reliably detected via NIP-10 root lookup
- Any future peer-context threading must not be applied to friend messages

## Open Tail

*(none)*

## Evidence

- transcript lines 2080-2098

