# C1 Evidence - LIB-001 View Subscribed Podcasts Library

Run: 2026-07-05T19:34:00Z on iPhone 17 / iOS 26.2 with `--UITestSeed`.

Catalog verdict: `LIB-001` is `pass_with_issues`.

Legacy runbook coverage: broader C1 filter/category and unsubscribe branches
remain follow-up evidence outside `LIB-001`.

## Evidence

| Artifact | UI critique | UX critique | Performance/accessibility notes |
| --- | --- | --- | --- |
| `assets/scenarios/c1-view-library/20260705T193400Z-all-podcasts.jpg` | The row hierarchy is readable and uses native list spacing. The visible state exposes title, episode/provider summary, `Following`, and chevron. No unplayed-count indicator or category/filter chip is visible. | The screen gives a clear path to search or add a show, but the scenario's filter/scope task has no visible entry point in this state. | UI tree has 69 nodes and the row is exposed as a button. Touch target appears large enough; filter accessibility could not be assessed because filters are absent. |
| `assets/scenarios/c1-view-library/20260705T193500Z-show-detail.jpg` | Show detail has clear title, description, episode count, and episode rows. Episode rows expose duration, unplayed/downloaded state, and play controls. | Navigating from the podcast row ultimately reached the expected show detail. Long-press unsubscribe was not tested. | UI tree has 128 nodes. Episode-row labels include state text, which is useful for VoiceOver; no scroll hitch was observed locally. |

## Current Result

Observed:

- All Podcasts screen lists seeded `This American Life`.
- The row exposes `Following` and `3 episodes - This American Life`.
- Show detail displays three episodes and a `Show options` button.

Adjacent branches not validated:

- Unplayed count on the podcast list row.
- Category/filter scoping and empty filtered state.
- Long-press unsubscribe context menu.

## Gaps

Do not read `LIB-001` as covering adjacent filter, context-menu, or unsubscribe
rows. Those need their own evidence records.
