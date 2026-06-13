---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - nip-46
  - bunker-signing
  - identity
supersedes:
  - 2026-06-13-4-swift-nip-46-bunker-signing-path
related_claims: []
source_lines:
  - 7814-7844
  - 7846-7861
captured_at: 2026-06-13T02:56:17Z
---

# Episode: NIP-46 bunker signing: Swift duplicate path never existed

## Prior State

A Swift header comment in UserIdentityStore+Publishing.swift claimed 'bunker stays Swift-side,' implying a duplicate NIP-46 signing path existed in Swift that should be retired. The BACKLOG item social-bunker-signing-kernel was open to track this supposed migration.

## Trigger

Deep verification of NMP kernel source showed sign_active_nonblocking already handles NIP-46 bunker accounts via PendingSign broker round-trip, and the Swift implementation already dispatched everything through the kernel. There was never a Swift NIP-46 signing branch.

## Decision

Correct the false header comment in UserIdentityStore+Publishing.swift; fix a 'user's nsec' misnomer in nmp_dispatch.rs; close social-bunker-signing-kernel as DONE. Retain NostrSigner.swift (contains NostrSignerError used by SignedEventsRegistry for the separate sign-event-for-return path).

## Consequences

- No behavior change — PR #424 is comment/doc-only (zero non-comment code lines changed).
- NostrSigner.swift must not be deleted — it serves the sign-event-for-return path, not social publishing.

## Open Tail

- nip73-formatting-kernel remains open but low priority (tag formatting already kernel-owned; only raw identifier encoding remains Swift-side).

## Evidence

- transcript lines 7814-7844
- transcript lines 7846-7861

