---
type: episode-card
date: 2026-05-17
session: 144a71df-cae7-4a4e-a996-64db4a3bef0b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/144a71df-cae7-4a4e-a996-64db4a3bef0b.jsonl
salience: architecture
status: active
subjects:
  - nostrstack-relay-lifecycle
  - discovery-always-on
  - nostr-enabled-flag-scope
supersedes: []
related_claims: []
source_lines:
  - 1173-1174
  - 1290-1306
  - 1357-1361
  - 1401-1408
captured_at: 2026-06-12T12:41:01Z
---

# Episode: Decouple discovery relay connectivity from agent Nostr toggle

## Prior State

NostrStack.start() gated all relay connectivity on `settings.nostrEnabled` — if the agent's Nostr toggle was off, the relay pool disconnected entirely, causing the Add Podcast → Nostr tab to show 'Nostr not configured' and return empty results

## Trigger

User correction: 'Podcast f4 retrieval has NOTHING to do with whether the agent is fucking active on nostr or not! The app should be connected to nostr regardless of whether the agent is active on nostr or not!!!!'

## Decision

NostrStack.start() now always connects to discovery relays (relay.primal.net and the configured/default relay) regardless of `nostrEnabled`. The `nostrEnabled` flag now only gates agent-specific Nostr features (publishing events, agent responder, DM relay service), not read-only discovery. NostrDiscoverForm.configuredRelayURL falls back to the hardcoded discovery relay when the user hasn't configured one.

## Consequences

- NIP-F4 podcast browsing works immediately without any Nostr setup by the user
- `nostrEnabled` scope narrowed: it no longer controls relay pool connectivity, only agent write-path features
- NostrStack.relaysConnected becomes true on launch even if the user never visits agent settings

## Open Tail

*(none)*

## Evidence

- transcript lines 1173-1174
- transcript lines 1290-1306
- transcript lines 1357-1361
- transcript lines 1401-1408

