---
type: episode-card
date: 2026-05-17
session: 144a71df-cae7-4a4e-a996-64db4a3bef0b
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/144a71df-cae7-4a4e-a996-64db4a3bef0b.jsonl
salience: reversal
status: superseded
subjects:
  - nip-74-to-nip-f4
  - podcast-protocol
  - kind-10154
  - kind-54
supersedes: []
related_claims: []
source_lines:
  - 1-1
  - 21-61
  - 843-859
captured_at: 2026-06-12T12:41:01Z
---

# Episode: Migrate podcast protocol from NIP-74 to NIP-F4

## Prior State

Podcast Nostr implementation used NIP-74: kind:30074 for shows, kind:30075 for episodes, d-tags for parameterised replaceable deduplication, agent's key signed everything, `imeta` tags for audio metadata, `summary` tag for descriptions

## Trigger

User directive: 'we are changing the podcast nip implementation -- no longer nip-74, we now use NIP-F4'

## Decision

Full migration to NIP-F4: kind:10154 for shows (replaceable, no d-tag), kind:54 for episodes (regular event), `description` tag replaces `summary`, `audio` tag replaces `imeta`, show coordinate is `10154:<pubkey>` with no d-tag, episode guid equals event ID. NostrPodcastPublisher and NostrPodcastDiscoveryService rewritten. All kind-number references and user-facing strings updated across the codebase.

## Consequences

- Discovery queries changed from filtering by kind+d-tag to filtering by kind+author pubkey
- Episode identifiers changed from naddr to npub/event-ID
- Existing kind:30074/30075 events on relays are now orphaned (no migration path for old events)
- All agent tool schema descriptions and user-facing UI strings updated to reference NIP-F4

## Open Tail

- Relay operators need to index kind:10154 and kind:54 for discovery to work

## Evidence

- transcript lines 1-1
- transcript lines 21-61
- transcript lines 843-859

