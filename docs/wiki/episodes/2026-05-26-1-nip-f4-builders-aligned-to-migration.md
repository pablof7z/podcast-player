---
type: episode-card
date: 2026-05-26
session: 378a594b-f095-461d-a035-4d3afca30d5e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/378a594b-f095-461d-a035-4d3afca30d5e.jsonl
salience: reversal
status: active
subjects:
  - nip-f4
  - podcast-discovery
  - nostr-event-schema
  - tag-layout
supersedes:
  - 2026-05-17-1-migrate-podcast-protocol-from-nip-74
related_claims: []
source_lines:
  - 1-3
  - 301-355
  - 466-480
captured_at: 2026-06-12T12:45:35Z
---

# Episode: NIP-F4 builders aligned to migration contract — removed d/a/published_at tags, switched summary→description, imeta→audio

## Prior State

The show and episode builders still emitted the old NIP-74 tag set: d tags on both event types, a tag on episodes, published_at tag, summary tag, and imeta blocks. The parser required a d tag. NIP74Show carried d_tag and summary fields. The coordinate format was "10154:<pubkey>:<d-tag>". The signer parameter was agent_pubkey.

## Trigger

User identified the mismatch between the migration plan (docs/plan/pod0-nostr-publishing.md:23 — no d tags, no a tag, description, audio) and the actual builders (episode.rs:48, show.rs:36 still emitting d, published_at, a, summary, imeta).

## Decision

Rewrote both builders and the show parser to match the NIP-F4 contract: removed d and a tags entirely; replaced summary with description; replaced imeta blocks with ["audio", url, mime] tags; removed published_at (timestamp comes from event created_at at sign time); changed signer from agent_pubkey to podcast_pubkey; changed NIP74Show.coordinate() to "10154:<pubkey>" (pubkey-only, no d-tag component); simplified ImetaInfo to mime_type only; dropped mandatory d-tag requirement in the parser.

## Consequences

- Show events are now identified by pubkey alone (no d-tag coordinate component); episodes discovered by filtering kind:54 authored by podcast pubkey
- NIP74Show struct lost d_tag field; summary renamed to description throughout
- Coordinate format change from "10154:<pubkey>:<d-tag>" to "10154:<pubkey>" is a wire-breaking change — any consumer expecting the old format must be updated
- Episode builders no longer accept show_pubkey/show_d parameters; ImetaInfo reduced to mime_type only
- Parser no longer returns MissingTag("d") — d tag is not required for NIP-F4 shows

## Open Tail

- ShowReference is preserved for parsing legacy a tags but may need a deprecation path
- The episode parser was not changed in this session (no round-trip test covering it); may still carry NIP-74 assumptions
- The actions module still references nip74 in wire-shape action IDs (podcast.nip74.publish_show etc.)

## Evidence

- transcript lines 1-3
- transcript lines 301-355
- transcript lines 466-480

