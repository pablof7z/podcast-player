---
type: episode-card
date: 2026-05-14
session: 02078283-91db-41b1-80f8-989daef628ac
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/02078283-91db-41b1-80f8-989daef628ac.jsonl
salience: product
status: active
subjects:
  - nostrconnect-view
  - remote-signer-ux
supersedes: []
related_claims: []
source_lines:
  - 2013-2016
  - 2243-2244
captured_at: 2026-06-12T12:30:07Z
---

# Episode: Cancel button hidden after pairing to prevent session teardown

## Prior State

The Cancel toolbar button was always visible in NostrConnectView and always called `disconnectRemoteSigner()`, regardless of pairing state.

## Trigger

Advisor review identified that after successful nostrconnect pairing, tapping Cancel would unconditionally call `disconnectRemoteSigner()`, tearing down the just-established bunker session — a destructive user-visible bug.

## Decision

Added an `isPaired` computed property (checking `remoteSignerState == .connected`) and conditionally hides the Cancel toolbar button when paired, so users cannot accidentally disconnect after successful pairing.

## Consequences

- Users in connected state see no Cancel button — they must use other navigation to leave the screen
- The paired session remains intact until the user explicitly logs out or the app is reinstalled

## Open Tail

*(none)*

## Evidence

- transcript lines 2013-2016
- transcript lines 2243-2244

