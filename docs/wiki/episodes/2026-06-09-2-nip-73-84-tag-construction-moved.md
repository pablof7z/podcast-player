---
type: episode-card
date: 2026-06-09
session: 04b5f843-fdbe-4aa1-ae41-6770eac82957
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/04b5f843-fdbe-4aa1-ae41-6770eac82957.jsonl
salience: architecture
status: active
subjects:
  - social-publishing
  - nip-73
  - nip-84
  - kernel-ownership
supersedes: []
related_claims: []
source_lines:
  - 2025-2377
captured_at: 2026-06-12T13:40:38Z
---

# Episode: NIP-73/84 tag construction moved from Swift shell to kernel

## Prior State

Swift's UserIdentityStore+Publishing assembled NIP-73/84 tag arrays (["i","podcast:item:guid:…#t=start,end"], ["r",…], ["context",…]) and dispatched pre-built `tags` to the Rust kernel, which passed them through verbatim

## Trigger

Issue #355 — NMP-conformance scan found that NIP tag construction is Nostr semantics that belong in the kernel per doctrine D0/D5; the codebase already did this correctly elsewhere (LivePeerEventPublisher passes typed fields)

## Decision

Rust SocialAction enum now takes typed semantic fields (episode_coord, start_ms, end_ms, caption, etc.); handle_publish_highlight/handle_publish_note build NIP-73/84 tags internally from those fields; Swift passes only the typed fields, not tag arrays

## Consequences

- Swift no longer needs knowledge of NIP-73/84 tag wire formats
- Adding or modifying NIP tag variants requires only Rust changes
- Wire contract changed from {op, content, tags} to {op, content, episode_coord, start_ms, end_ms, caption, …}
- 24 Rust unit tests assert exact tag output, making future NIP spec changes verifiable

## Open Tail

*(none)*

## Evidence

- transcript lines 2025-2377

