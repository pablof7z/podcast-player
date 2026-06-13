---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: active
subjects:
  - kernelsigner-removal
  - sign-event-for-return-removal
  - nostr-signer-protocol
supersedes:
  - 2026-06-13-2-kernelsigner-and-signeventforreturn-chain-removed-as
related_claims: []
source_lines:
  - 6944-6984
  - 6989-7031
  - 7270-7277
captured_at: 2026-06-13T01:45:27Z
---

# Episode: KernelSigner + signEventForReturn dead-code removal

## Prior State

KernelSigner struct (sole production conformer of NostrSigner protocol), NostrSigner protocol itself, NostrEventDraft struct, and the full signEventForReturn chain (KernelSigner.sign() → KernelModel.signEventForReturn → PodcastHandle.signEventForReturn) existed as dead code. The protocol had zero conformers besides KernelSigner.

## Trigger

Explicit cleanup via BACKLOG item kernelsigner-deadcode-removal; Opus planner confirmed KernelSigner is dead.

## Decision

Delete KernelSigner, NostrSigner protocol, NostrEventDraft, and the full signEventForReturn chain. Retain NostrSignerError (still used by KernelBridge + tests), SignedEventsRegistry (tested D13 seam), and the FFI declaration. Fix 3 stale doc sites (BACKLOG relay-config marked DONE, register.rs comment corrected, agent-to-agent-kind1 BACKLOG corrected).

## Consequences

- D13 kernel signing seam simplified — only SignedEventsRegistry and NostrSignerError remain
- Orphan-trap rule enforced: build-for-testing verified zero orphaned Swift references
- NostrSignerError retained as the canonical error type for the remaining signing path

## Open Tail

*(none)*

## Evidence

- transcript lines 6944-6984
- transcript lines 6989-7031
- transcript lines 7270-7277

