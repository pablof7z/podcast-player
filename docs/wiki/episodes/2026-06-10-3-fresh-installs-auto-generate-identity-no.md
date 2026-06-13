---
type: episode-card
date: 2026-06-10
session: 4243e533-7577-4916-afae-773f1c45b9f2
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/4243e533-7577-4916-afae-773f1c45b9f2.jsonl
salience: product
status: active
subjects:
  - auto-keygen
  - identity-defaults
  - android-identity
supersedes: []
related_claims: []
source_lines:
  - 1-3
  - 5814-5827
  - 6098-6127
captured_at: 2026-06-12T13:43:48Z
---

# Episode: Fresh installs auto-generate identity; 'no identity' state is never user-visible

## Prior State

The app could be in a 'no identity' / 'Not signed in' state for both the agent and human user on first launch. The 'Generate Key Pair' button existed but did not update the UI after being tapped (due to the push-frame and signal bugs above).

## Trigger

User directive: 'there should be NO state where this is a thing — if no identity exists for either we should create it for them'

## Decision

Android's PodcastRoot LaunchedEffect now checks `first.activeAccount == null && KeystoreManager.loadNsec(context) == null` after the initial snapshot pull and automatically calls `IdentityActions.generate(bridge)`. The 'Generate Key Pair' button also performs an explicit `onSnapshotPull()` after dispatching Generate to get an immediate UI update.

## Consequences

- Fresh installs and data resets always have an auto-generated local key identity within seconds of first launch
- The 'Generate Key Pair' button now visibly transitions the UI to SignedInState
- The 'Not signed in' state is only briefly visible during the async generate+pull cycle on first launch

## Open Tail

- Agent identity may still need separate auto-generation if it uses a different key path

## Evidence

- transcript lines 1-3
- transcript lines 5814-5827
- transcript lines 6098-6127

