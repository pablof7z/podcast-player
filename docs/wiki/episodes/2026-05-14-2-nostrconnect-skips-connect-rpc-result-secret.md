---
type: episode-card
date: 2026-05-14
session: 02078283-91db-41b1-80f8-989daef628ac
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/02078283-91db-41b1-80f8-989daef628ac.jsonl
salience: root-cause
status: active
subjects:
  - nip46-nostrconnect
  - remote-signer
  - connect-rpc
supersedes: []
related_claims: []
source_lines:
  - 1405-1411
  - 2057-2079
  - 2185-2186
captured_at: 2026-06-12T12:30:07Z
---

# Episode: Nostrconnect skips connect RPC — result==secret IS the ack

## Prior State

The NIP-46 bunker flow calls `connect` RPC as the first message after establishing a transport. The natural assumption was that nostrconnect would also need to call `connect` after discovering the signer.

## Trigger

Advisor review identified that in the nostrconnect flow, the signer's `result == secret` response already constitutes the connection acknowledgment. Sending a `connect` RPC would trigger a duplicate `auth_url` challenge on most bunkers.

## Decision

Added `finishNostrConnect(relayURL:)` method to RemoteSigner that creates a fresh transport with the discovered pubkey, sets the conversation key, and calls ONLY `get_public_key` — explicitly skipping the `connect` RPC entirely.

## Consequences

- Nostrconnect-paired sessions avoid spurious auth_url challenges that would confuse the user
- Warm reconnect via `resumeRemote` still uses `connect` RPC, which is correct for bunker-URI-initiated sessions but may re-prompt on some bunkers for nostrconnect sessions saved with `secret: nil`
- The nostrconnect flow has a fundamentally different RPC sequence than bunker URI flow: discovery → get_public_key vs. connect → get_public_key

## Open Tail

- Warm reconnect for nostrconnect-paired sessions (secret: nil) may still trigger auth_url challenges on some bunkers — needs real-device testing with Amber and Primal

## Evidence

- transcript lines 1405-1411
- transcript lines 2057-2079
- transcript lines 2185-2186

