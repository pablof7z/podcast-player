---
type: episode-card
date: 2026-05-13
session: 513924f8-3b98-47b0-a84a-38086416581a
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/513924f8-3b98-47b0-a84a-38086416581a.jsonl
salience: root-cause
status: active
subjects:
  - toolbar-buttons
  - liquid-glass
  - ios26-compatibility
supersedes: []
related_claims: []
source_lines:
  - 735-1287
captured_at: 2026-06-12T12:12:08Z
---

# Episode: iOS 26 toolbar doctrine: don't manually apply glass style to nav bar items

## Prior State

Toolbar buttons across the app explicitly used .buttonStyle(.glass) + .buttonBorderShape(.circle), and FeedbackView wrapped toolbar buttons in a GlassEffectContainer

## Trigger

User reported that toolbar buttons on the Home tab looked wrong — not like normal liquid glass buttons

## Decision

Removed .buttonStyle(.glass) and .buttonBorderShape(.circle) from all navigation bar ToolbarItem buttons; removed GlassEffectContainer from FeedbackView's toolbar; iOS 26 applies liquid glass automatically to nav bar items and manual styling creates a double-glass effect

## Consequences

- iOS 26 nav bar toolbar items now render with system-default liquid glass
- Established doctrine: never manually apply glass button style to nav bar toolbar items
- Fixed in RootView (sparkles + gear), HomeView (plus), AgentChatView (3 buttons), FeedbackView (3 buttons + GlassEffectContainer)

## Open Tail

- Other views using .buttonStyle(.glass) outside toolbars (AgentIdentityHero, HomeEmptyStates, EditProfileView, etc.) may need separate evaluation — those are in sheet/list content, not nav bars

## Evidence

- transcript lines 735-1287

