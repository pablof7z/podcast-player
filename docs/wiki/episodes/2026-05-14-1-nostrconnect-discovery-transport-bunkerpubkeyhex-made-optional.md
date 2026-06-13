---
type: episode-card
date: 2026-05-14
session: 02078283-91db-41b1-80f8-989daef628ac
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/02078283-91db-41b1-80f8-989daef628ac.jsonl
salience: architecture
status: active
subjects:
  - nip46-nostrconnect
  - remote-signer-client
  - discovery-transport
supersedes: []
related_claims: []
source_lines:
  - 1393-1403
  - 2039-2055
captured_at: 2026-06-12T12:30:07Z
---

# Episode: Nostrconnect discovery transport — bunkerPubkeyHex made optional

## Prior State

RemoteSignerClient required a known bunkerPubkeyHex (non-optional String) at init time, and the REQ subscription always included an `authors` filter scoped to that pubkey.

## Trigger

Nostrconnect pairing requires the client to discover the signer's pubkey from scratch — the whole point is the client doesn't know who will respond. An `authors` filter would reject valid responses from unknown signers.

## Decision

Changed `bunkerPubkeyHex` from `String` to `String?` in RemoteSignerClient init and stored property. When nil, `sendSubscription()` omits the `authors` filter entirely, accepting inbound events from any sender. The RemoteSignerTransportFactory typealias was updated to match.

## Consequences

- Discovery-mode client instances now accept events from any relay participant, requiring per-sender NIP-44 decryption attempts to find the correct signer
- Bunker-initiated flows (bunker URI) continue to pass a concrete pubkey; only nostrconnect flows pass nil
- The discovery transport must be torn down after identifying the signer and replaced with a targeted transport for subsequent RPC calls

## Open Tail

*(none)*

## Evidence

- transcript lines 1393-1403
- transcript lines 2039-2055

