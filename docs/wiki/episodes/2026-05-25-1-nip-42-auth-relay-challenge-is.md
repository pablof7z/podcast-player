---
type: episode-card
date: 2026-05-25
session: c3094761-69de-4cc9-a097-80d38f00114e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c3094761-69de-4cc9-a097-80d38f00114e.jsonl
salience: root-cause
status: active
subjects:
  - user-identity-wiring-tests
  - nip-42-auth
  - feedback-relay-client
  - fire-and-forget-publishing
supersedes: []
related_claims: []
source_lines:
  - 508-753
captured_at: 2026-06-12T12:44:06Z
---

# Episode: NIP-42 AUTH relay challenge is the test-contamination vector

## Prior State

Two UserIdentityWiringTests failures (testAddNoteAgentAuthorDoesNotSign, testAgentToolCreateNoteDoesNotSign) were attributed to fire-and-forget Tasks from prior 'does sign' tests lingering and reading old RecordingSigner via the singleton. A 500ms drain sleep in tearDown was attempted as a fix.

## Trigger

Diagnostic output added to failing assertions revealed 4 × kind:22242 (NIP-42 AUTH) sign calls hitting each 'does not sign' test's RecordingSigner. The real relay wss://relay.tenex.chat sends auth-required challenges, and FeedbackRelayClient.publish() responds by calling authSigner.sign(kind:22242).

## Decision

Reverted the 500ms drain sleep (ineffective — the relay timeout is 8 seconds). Root cause confirmed: fire-and-forget Tasks from 'does sign' tests connect to the real relay, and due to Swift @MainActor cooperative scheduling, those Tasks can start executing AFTER the next test's setUp replaces self.signer on the singleton. The guard-let capture in publishUserNote/publishUserClip then reads the NEW test's RecordingSigner, and when the relay challenges with NIP-42 AUTH, the sign(kind:22242) call lands on that new RecordingSigner — producing spurious calls that fail the 'must not reach the user signer' assertion.

## Consequences

- Timing-based drains (sleeps) cannot fix this — the WebSocket timeout (8s) far exceeds any reasonable tearDown delay, and cooperative scheduling makes Task start order nondeterministic.
- The fix must either mock FeedbackRelayClient in tests (inject a relay that never sends AUTH challenges) or restructure the publish path to avoid process-wide singleton + fire-and-forget Task patterns.
- FeedbackRelayClient.publish(authSigner:)'s NIP-42 auth flow is a side-effect channel that must be accounted for in any test isolation strategy.
- The guard-let-signer capture pattern in publishUserNote/publishUserClip reads self.signer at Task execution time, not Task creation time, making it vulnerable to cross-test contamination under cooperative scheduling.

## Open Tail

- Fix not yet applied — need to either inject a mock FeedbackRelayClient in tests, cancel pending Tasks in tearDown, or restructure the signing/publishing contract to be testable without real relay connections.
- AdSegmentDetectorTests also has isolation warnings (main actor-isolated property mutation from nonisolated context) that need @MainActor annotation.

## Evidence

- transcript lines 508-753

