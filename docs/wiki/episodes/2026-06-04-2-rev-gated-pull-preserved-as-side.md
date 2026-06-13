---
type: episode-card
date: 2026-06-04
session: e1ab0629-64bc-4383-bd22-c0843ca16a99
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/e1ab0629-64bc-4383-bd22-c0843ca16a99.jsonl
salience: root-cause
status: active
subjects:
  - apply-audio-report-side-channel
  - background-rev-surfacing
supersedes:
  - 2026-06-04-1-playback-position-ticks-no-longer-rebuild
related_claims: []
source_lines:
  - 5969-5998
  - 6097-6105
captured_at: 2026-06-12T13:15:22Z
---

# Episode: Rev-gated pull preserved as side-channel for background work

## Prior State

The removed per-tick full snapshot pull was the only mechanism that surfaced background rev bumps (inbox triage, categorization, relay updates) to the UI during continuous playback. Removing it entirely would cause UI staleness for those events until playback stopped.

## Trigger

Self-identified blind spot during implementation review: removing the per-tick pull would silently break background-work surfacing during playback.

## Decision

applyAudioReport still calls pullPodcastSnapshotIfChanged on every tick, but since ticks no longer bump rev, this is now a cheap atomic probe (no decode when rev unchanged) that still surfaces real background changes instantly when rev does advance from other sources.

## Consequences

- Background work (triage, categorization, comments, relay) continues to surface to the UI during playback with zero added latency
- The pull is near-free when no background rev bump occurred (single atomic compare vs full JSON decode)
- The side-channel is now explicit and intentional rather than incidental

## Open Tail

*(none)*

## Evidence

- transcript lines 5969-5998
- transcript lines 6097-6105

