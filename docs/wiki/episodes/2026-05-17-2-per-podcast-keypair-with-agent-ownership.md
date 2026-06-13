---
type: episode-card
date: 2026-05-17
session: 144a71df-cae7-4a4e-a996-64db4a3bef0b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/144a71df-cae7-4a4e-a996-64db4a3bef0b.jsonl
salience: architecture
status: active
subjects:
  - per-podcast-keypair
  - podcast-keystore
  - kind-10064
  - ownership-model
supersedes: []
related_claims: []
source_lines:
  - 112-123
  - 556-575
  - 576-597
  - 786-830
captured_at: 2026-06-12T12:41:01Z
---

# Episode: Per-podcast keypair with agent ownership claim

## Prior State

Agent's single Nostr key signed all podcast show and episode events; shows were distinguished by d-tags within that one key's namespace

## Trigger

NIP-F4 has no d-tag on kind:54, making single-key multi-podcast discovery impossible — assistant identified this as a critical design question; user resolved: 'Per-podcast keypair, the agent claims ownership, not the user'

## Decision

Each podcast gets its own Nostr keypair generated on creation and stored in Keychain via PodcastKeyStore (keyed by podcast UUID). The podcast key signs its own kind:10154 and kind:54 events. After each show publish, the agent publishes kind:10064 (author claim) linking its own pubkey to the podcast's pubkey. PodcastKeyStore handles create/read/delete; deletion of a podcast also purges its Keychain entry.

## Consequences

- LiveAgentOwnedPodcastManager.podcastSigner(for:) generates/retrieves per-podcast keys; agentSigner() remains separate for kind:10064 claims
- nostrAddr() returns npub (podcast's pubkey) instead of naddr
- Podcast model stores ownerPubkeyHex = podcast's own pubkey (not agent's)
- Keychain key lifecycle tied to podcast lifecycle — deletePodcast must call PodcastKeyStore.deletePrivateKey()
- Agent tool responses changed from returning naddr to returning npub/event_id

## Open Tail

*(none)*

## Evidence

- transcript lines 112-123
- transcript lines 556-575
- transcript lines 576-597
- transcript lines 786-830

