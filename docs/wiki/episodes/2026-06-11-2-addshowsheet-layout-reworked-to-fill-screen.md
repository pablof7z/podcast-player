---
type: episode-card
date: 2026-06-11
session: ec1fb244-f19d-4667-8784-28bb26786eb9
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/ec1fb244-f19d-4667-8784-28bb26786eb9.jsonl
salience: product
status: active
subjects:
  - add-show-layout
  - liquid-glass-segments
supersedes: []
related_claims: []
source_lines:
  - 2-2
  - 385-417
captured_at: 2026-06-12T13:49:23Z
---

# Episode: AddShowSheet layout reworked to fill screen and tighten segments

## Prior State

AddShowSheet had a Spacer(minLength: 0) at the bottom leaving an ugly empty white gap below the podcast list; excessive spacing (lg) between the segment picker and content; OPML segment used a negative-padding hack; From URL segment lacked keyboard-dismiss ScrollView

## Trigger

User reported: 'the list is contained (leaving an ugly empty white space under the list), the search/nostr/from url/opml doesn't seem to be properly using segment control — this could be greatly improved'

## Decision

Removed the Spacer; content now fills available space via .frame(maxWidth: .infinity, maxHeight: .infinity); VStack spacing between segment picker and content reduced from lg to 0 for flush layout; OPML negative-padding hack removed; From URL segment wrapped in ScrollView with keyboard dismiss

## Consequences

- No more white gap below podcast list content
- Segment picker sits flush against content area per liquid glass design language
- From URL form is scrollable and dismisses keyboard on drag
- OPML import no longer relies on a layout hack

## Open Tail

*(none)*

## Evidence

- transcript lines 2-2
- transcript lines 385-417

