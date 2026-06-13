---
type: episode-card
date: 2026-05-13
session: d0e6775b-4ac9-4467-b961-7e78de0f61eb
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/d0e6775b-4ac9-4467-b961-7e78de0f61eb.jsonl
salience: product
status: active
subjects:
  - ai-inbox-triage
  - archive-recovery
  - playback-state
supersedes: []
related_claims: []
source_lines:
  - 923-923
  - 1037-1066
captured_at: 2026-06-12T12:16:54Z
---

# Episode: Playing an archived episode auto-clears the archive

## Prior State

Playing an archived episode from the show page did not clear the archive state. Pausing would cause Continue Listening to hide it again — hostile recoverability.

## Trigger

Codex review identified that archive state wasn't cleared on play (line 923).

## Decision

Added onClearTriageDecision closure to PlaybackState (no-op default, wired to store.clearTriageDecision in RootView). Invoked in setEpisode when the loaded episode is triage-archived. Every playback path goes through setEpisode, so all entry points are covered.

## Consequences

- The implicit contract is: playing an episode rescues it from archive permanently
- PlaybackState remains decoupled from AppStateStore via closure injection (matching existing pattern for onPersistPosition, onFlushPositions, etc.)
- New playback entry points must go through setEpisode or the rescue won't fire

## Open Tail

*(none)*

## Evidence

- transcript lines 923-923
- transcript lines 1037-1066

