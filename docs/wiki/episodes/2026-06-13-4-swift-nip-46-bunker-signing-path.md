---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - nip46-bunker-signing
  - identity-publishing
  - d13-retirement
supersedes: []
related_claims: []
source_lines:
  - 7812-7844
captured_at: 2026-06-13T02:30:19Z
---

# Episode: Swift NIP-46 bunker signing path never existed — D13 item was already done

## Prior State

A header comment in UserIdentityStore+Publishing.swift claimed 'bunker stays Swift-side', and BACKLOG item social-bunker-signing-kernel (D13) was open as work to retire a presumed duplicate Swift NIP-46 signing path.

## Trigger

Deep verification of NMP kernel source confirmed: sign_active_nonblocking → PendingSign broker round-trip handles all bunker signing, with an e2e nip46_bunker_signing.rs test proving it. The Swift code already dispatched everything through the kernel — no Swift signing branch ever existed.

## Decision

The 'bunker stays Swift-side' comment was false. D13 is already done — no behavior change or Swift deletion needed. Fixed the stale comment and misnomer in nmp_dispatch.rs; marked social-bunker-signing-kernel DONE in BACKLOG.

## Consequences

- NostrSigner.swift retained — it's used by KernelBridge's SignedEventsRegistry for the separate sign-event-for-return path
- nip73-formatting-kernel remains open but low priority (only raw identifier encoding of podcast:item:guid remains Swift-side)

## Open Tail

*(none)*

## Evidence

- transcript lines 7812-7844

