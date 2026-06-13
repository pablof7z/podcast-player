---
type: episode-card
date: 2026-06-05
session: b4d663c7-85f0-4086-9bdc-030177ef43e5
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/b4d663c7-85f0-4086-9bdc-030177ef43e5.jsonl
salience: product
status: active
subjects:
  - clippings-orphan-render
  - clip-row-guard
  - clippings-card-optional-episode
supersedes: []
related_claims: []
source_lines:
  - 1249-1290
  - 1398-1450
  - 1497-1550
captured_at: 2026-06-12T13:19:01Z
---

# Episode: Clippings ghost section header for orphaned clips

## Prior State

ClippingsView's `clipRow` guarded on `store.episode(id:)` — when a clip's episode had aged out of the feed (unsubscribed/pruned), the row rendered nothing while its date-bucket Section header ('EARLIER') still appeared, leaving a ghost heading over blank space.

## Trigger

Device UI survey of the Clippings tab revealed a lone 'EARLIER' section header with no rows underneath. Code inspection confirmed `if let episode = store.episode(...)` silently dropped the row, even though `ClippingsCard` already accepts `episode: Episode?` with graceful degradation (placeholder artwork, omitted title, caption/quote still shown).

## Decision

Remove the guard; render clip rows unconditionally and gate only episode-navigation on a resolvable episode. `ClippingsCard`'s existing optional-episode design handles the nil case as intended. Committed as `19b46163`.

## Consequences

- Orphaned clips (episode unsubscribed or feed-pruned) now render as cards with placeholder art and their own caption/transcript instead of disappearing entirely.
- Empty-state path verified correct on simulator ('No Clippings Yet' with no ghost headers).
- Orphan-case visual reproduction on the running app remains incomplete (the device was locked; the sim had no real orphan data to test with).
- A whats-new.json entry was added for the fix.

## Open Tail

- Finish orphan-case visual verification: seed a clip whose episode is absent, confirm a card renders instead of a ghost header.
- The resume/reopen label ('Resume' on reopening a played episode) remains unconfirmed — P0-04 tests were confounded by stale bindings, feed reorder, and broken back-nav. Not a confirmed defect; needs a confound-free test.

## Evidence

- transcript lines 1249-1290
- transcript lines 1398-1450
- transcript lines 1497-1550

