# I3 Evidence - SET-001 Playback Settings

Run: 2026-07-05T19:39:00Z on iPhone 17 / iOS 26.2 with `--UITestSeed`.

Verdict: `incomplete`.

## Evidence

| Artifact | UI critique | UX critique | Performance/accessibility notes |
| --- | --- | --- | --- |
| `assets/scenarios/i3-playback-settings/20260705T193900Z-player-settings-baseline.jpg` | The settings hierarchy is clear: Default Speed, skip intervals, gesture actions, and toggles are grouped with explanatory copy. | The default values are understandable from the row summaries. Pickers were visible but not changed in this pass. | UI tree has 220 nodes. Buttons and switches expose labels and values, including `Auto-mark played at end` value `1`. |
| `assets/scenarios/i3-playback-settings/20260705T193930Z-auto-mark-off.jpg` | The toggle state change is visually clear and stays in place, so no layout shift is introduced. | Direct toggle feedback is immediate. | UI tree reports `Auto-mark played at end` value `0`. |
| `assets/scenarios/i3-playback-settings/20260705T194000Z-persisted-after-navigation.jpg` | Returning to the screen preserves the same layout and summary values. | Navigation-away/back persistence is understandable and avoids redundant entry. | UI tree again reports `Auto-mark played at end` value `0`, proving persistence across navigation in the current run. |

## Current Result

Observed:

- Settings -> Player opens successfully.
- Default speed, skip back, skip forward, double-tap, triple-tap, auto-mark,
  auto-play-next, and footer copy are present.
- `Auto-mark played at end` toggled from on to off and persisted after leaving
  Player and re-entering it.

Not validated:

- Changing default speed or skip interval picker values.
- Headphone gesture picker changes.
- Persistence across relaunch.
- Propagation into player/lock-screen skip controls.

## Gap

I3 has current evidence for the route and one toggle persistence path, but not
for every picker and relaunch acceptance criterion.
