---
type: episode-card
date: 2026-05-15
session: d0447a6c-e8a4-4913-a5bd-cd462c96487a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0447a6c-e8a4-4913-a5bd-cd462c96487a.jsonl
salience: product
status: active
subjects:
  - retroactive-nostr-publishing
  - podcast-visibility
  - owned-podcasts
supersedes: []
related_claims: []
source_lines:
  - 1109-1117
  - 1377-1379
captured_at: 2026-06-12T12:33:39Z
---

# Episode: Retroactive episode publishing when podcast flips from private to public

## Prior State

When update_podcast changed a podcast from private to public, only the show-level NIP-74 event was published. Existing episodes remained unpublished to Nostr, creating orphan content.

## Trigger

Discovery that going public leaves episodes invisible on Nostr unless explicitly published one by one.

## Decision

update_podcast now detects private→public visibility transitions and serially publishes all existing episodes as kind:30075 events. The response includes an episodes_published_to_nostr count.

## Consequences

- No orphan episodes remain when a podcast transitions to public visibility
- Serial publishing (not concurrent) due to Swift 6 sending-closure constraints
- episodes_published_to_nostr count gives the agent visibility into how many episodes were retroactively published

## Open Tail

- Performance implications for podcasts with very large back catalogs going public

## Evidence

- transcript lines 1109-1117
- transcript lines 1377-1379

