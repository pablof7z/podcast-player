---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: root-cause
status: active
subjects:
  - nip-46-bunker-signing
  - swift-identity-store
supersedes:
  - 2026-06-13-3-nip-46-bunker-signing-swift-duplicate
related_claims: []
source_lines:
  - 7811-7846
  - 7848-7861
captured_at: 2026-06-13T03:37:30Z
---

# Episode: D13 bunker signing: Swift NIP-46 path never existed — stale comment corrected

## Prior State

BACKLOG item D13 assumed a duplicate Swift NIP-46 signing path existed and needed retirement. The Swift header comment in UserIdentityStore+Publishing.swift stated 'bunker stays Swift-side,' creating the impression of a parallel signing branch.

## Trigger

Deep investigation of actual NMP kernel source (nmp-core) revealed: sign_active_nonblocking → PendingSign broker round-trip handles NIP-46; the Swift implementation already dispatches everything through the kernel via nmp_signer_broker_init. No Swift NIP-46 signing branch exists — the header comment was false.

## Decision

No behavior change. The 'retire the duplicate Swift NIP-46 signing path' task is resolved as truth-correction: the Swift path never existed. Corrected the stale header comment in UserIdentityStore+Publishing.swift and a misnomer in nmp_dispatch.rs. Marked social-bunker-signing-kernel DONE in BACKLOG.

## Consequences

- NostrSigner.swift retained — it defines NostrSignerError used by KernelBridge's SignedEventsRegistry for the sign-event-for-return path (separate from social publishing).
- nip73-formatting-kernel remains open but low priority (only raw identifier encoding remains Swift-side).

## Open Tail

*(none)*

## Evidence

- transcript lines 7811-7846
- transcript lines 7848-7861

