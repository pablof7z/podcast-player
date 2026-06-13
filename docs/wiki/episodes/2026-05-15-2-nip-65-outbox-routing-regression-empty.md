---
type: episode-card
date: 2026-05-15
session: 8c3708b9-22f2-404d-8534-c476e0cfcf75
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/8c3708b9-22f2-404d-8534-c476e0cfcf75.jsonl
salience: root-cause
status: active
subjects:
  - nip-65-outbox
  - nostr-publish
  - relay-routing
supersedes: []
related_claims: []
source_lines:
  - 2996-3004
  - 3326-3353
captured_at: 2026-06-12T12:37:22Z
---

# Episode: NIP-65 outbox routing regression: empty publish when author has no kind:10002

## Prior State

NostrPodcastPublisher fanned out to an explicit list of relay URLs passed by the caller (LiveAgentOwnedPodcastManager computed them from nostrPublicRelays + NIP65RelayFetcher.defaultRelays fallback). Publish always targeted known relays.

## Trigger

Write-path migration agent discovered that ndk.publish(event) with no explicit relay set relies on NIP-65 outbox routing — if the author hasn't published a kind:10002 event, the accepted-set is empty and the publish silently fails.

## Decision

NostrPodcastPublisher.publishViaNDK now passes the caller-supplied relayURLs array as the explicit `to:` parameter to ndk.publish(_:to:), restoring the previous guarantee that publish targets at least one known relay. The relayURLs init param is no longer vestigial — it's the explicit fallback when no outbox exists.

## Consequences

- Publish always has at least one relay target regardless of NIP-65 outbox state
- The `relayURLs` init param on NostrPodcastPublisher is now semantically required, not vestigial
- Future cleanup could add a dual-mode: outbox-first with explicit fallback

## Open Tail

- Verify that Podcastr identities always publish kind:10002 at creation time, making the explicit fallback defensive rather than load-bearing

## Evidence

- transcript lines 2996-3004
- transcript lines 3326-3353

