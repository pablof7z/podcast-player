---
type: episode-card
date: 2026-06-13
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
salience: reversal
status: superseded
subjects:
  - kernelsigner
  - sign-event-for-return
  - nostr-signer-protocol
supersedes: []
related_claims: []
source_lines:
  - 6944-6989
  - 6991-7010
captured_at: 2026-06-13T01:31:03Z
---

# Episode: KernelSigner and signEventForReturn chain removed as confirmed dead code

## Prior State

KernelSigner struct, NostrSigner protocol, NostrEventDraft, and the full signEventForReturn chain (KernelSigner.sign → KernelModel.signEventForReturn → PodcastHandle.signEventForReturn) existed in production code after being superseded by NIP-55 Amber sign-in (PR #417).

## Trigger

Opus architectural review confirmed KernelSigner as the sole conformer of NostrSigner and the entire sign-for-return chain as dead (no callers outside deleted KernelSigner).

## Decision

Deleted KernelSigner, NostrSigner protocol, and NostrEventDraft. Removed signEventForReturn chain from KernelBridge + KernelModel. Retained NostrSignerError (used by KernelBridge + SignedEventsRegistryTests) and SignedEventsRegistry + FFI decl (D13 signing seam for future use). Fixed 3 stale doc sites (BACKLOG relay-config marked DONE, register.rs comment block rewritten, agent-to-agent-kind1 BACKLOG corrected).

## Consequences

- These types are now historical; any future signing path must use the NIP-55 / Amber seam
- Swift-delete orphan trap rule triggered: xcodebuild build-for-testing verified (orphan-grep zero across production + tests)
- 227 net lines deleted

## Open Tail

*(none)*

## Evidence

- transcript lines 6944-6989
- transcript lines 6991-7010

