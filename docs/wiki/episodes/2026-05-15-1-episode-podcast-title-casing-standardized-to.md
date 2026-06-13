---
type: episode-card
date: 2026-05-15
session: a42285c2-863e-42d1-a433-e7bf25bcfc21
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a42285c2-863e-42d1-a433-e7bf25bcfc21.jsonl
salience: reversal
status: active
subjects:
  - episode-title-casing
  - podcast-name-casing
  - episode-detail-hero
  - home-resume-card
  - home-agent-pick-card
supersedes: []
related_claims: []
source_lines:
  - 1226-1240
  - 1565-1574
  - 1743-1755
captured_at: 2026-06-12T12:35:06Z
---

# Episode: Episode/podcast title casing standardized to natural case

## Prior State

EpisodeDetailHeroView showed episode titles in .uppercased() per UX-03 §6.1 'magazine-cover' spec; HomeResumeCard, HomeAgentPickCard, and PlayerClipSourceChip displayed podcast names with .textCase(.uppercase) and letter tracking. This created editorial differentiation between surfaces but was inconsistent with PlayerView and MiniPlayerView which showed natural case.

## Trigger

Consistency survey revealed that the same episode title appeared uppercased in detail view but normal-case in the player — a jarring inconsistency when navigating between surfaces.

## Decision

Removed .uppercased() from EpisodeDetailHeroView and .textCase(.uppercase) + tracking from HomeResumeCard, HomeAgentPickCard, and PlayerClipSourceChip. All episode and podcast names now render in their natural casing across every surface.

## Consequences

- The 'magazine-cover' editorial styling for episode detail is gone; the UX-03 §6.1 intent is overridden by the consistency principle
- Podcast names in home cards and clip chips no longer shout with uppercase tracking
- Episode titles are now visually consistent whether seen in detail, player, mini-player, or clip context

## Open Tail

- UX-03 §6.1 docstring still references magazine-cover styling — may need updating

## Evidence

- transcript lines 1226-1240
- transcript lines 1565-1574
- transcript lines 1743-1755

