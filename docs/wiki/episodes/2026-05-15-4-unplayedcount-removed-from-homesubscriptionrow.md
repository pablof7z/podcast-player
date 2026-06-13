---
type: episode-card
date: 2026-05-15
session: a42285c2-863e-42d1-a433-e7bf25bcfc21
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/a42285c2-863e-42d1-a433-e7bf25bcfc21.jsonl
salience: product
status: active
subjects:
  - home-subscription-row
  - unplayed-badge
supersedes: []
related_claims: []
source_lines:
  - 756-757
  - 1228-1229
  - 1650-1656
captured_at: 2026-06-12T12:35:06Z
---

# Episode: UnplayedCount removed from HomeSubscriptionRow

## Prior State

HomeSubscriptionRow received an unplayedCount parameter but only used it in the VoiceOver accessibility label — no visual badge was rendered. Every major podcast app shows a dot or number for unplayed episodes.

## Trigger

Consistency audit flagged the missing visual badge. The parameter was dead weight in the visual layer despite being wired in accessibility.

## Decision

Removed the unplayedCount parameter from HomeSubscriptionRow entirely rather than adding a visual badge. The call site in HomeSubscriptionListSection was updated to stop passing it.

## Consequences

- HomeSubscriptionRow no longer has any unplayed indicator — neither visual nor accessibility
- Simpler row interface with one fewer parameter
- If unplayed badges are desired later, the data is still available via AppStateStore.unplayedCount(forPodcast:)

## Open Tail

- This is a deliberate omission — a future decision may reintroduce unplayed badges on subscription rows

## Evidence

- transcript lines 756-757
- transcript lines 1228-1229
- transcript lines 1650-1656

