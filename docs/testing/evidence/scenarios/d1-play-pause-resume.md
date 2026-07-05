# D1 Evidence - PLAY-001 Play Starts Playback

Run: 2026-07-05T19:35:20Z on iPhone 17 / iOS 26.2 with `--UITestSeed`.

Catalog verdict: `PLAY-001` is `pass_with_issues`.

Adjacent playback coverage: pause/resume validation remains blocked by #718 and
belongs to PLAY-002 / PLAY-003 follow-up evidence.

Issue: https://github.com/pablof7z/podcast-player/issues/718

## Evidence

| Artifact | UI critique | UX critique | Performance/accessibility notes |
| --- | --- | --- | --- |
| `assets/scenarios/d1-play-pause-resume/20260705T193520Z-episode-detail.jpg` | Episode detail uses clear hierarchy: title, show, metadata, Play/Queue, downloaded state, chapters, notes/comments. | The primary Play action is obvious and reachable. | UI tree has 95 nodes. Play and chapter buttons have semantic labels. |
| `assets/scenarios/d1-play-pause-resume/20260705T193600Z-mini-player-playing.jpg` | Mini-player is compact and exposes title, chapter, elapsed time, Pause, skip-forward, and dismiss. | Playback feedback is immediate enough to understand that audio started. | Play tap produced a snapshot-settle warning, then UI showed elapsed `0:06`. After a 4.5s wait, elapsed advanced to `0:23`. |
| `assets/scenarios/d1-play-pause-resume/20260705T193700Z-full-player-paused.jpg` | Full player exposes chapters/transcript/notes and transport controls with accessibility identifiers. | Resume could not be validated because the seed reached an apparent end state. | UI tree has 183 nodes. Final labels were `1:00` and `-0:00`, while episode metadata said `5m`. |

## Current Result

Observed:

- Tapping Play starts playback and opens a mini-player.
- Mini-player elapsed time advanced from `0:06` to `0:23` in current evidence.
- Full player controls render with `player-play-pause`, skip back, skip forward,
  chapters, transcript, and notes controls.

Adjacent blocked coverage:

- Pause/resume from a held mid-episode position.
- Mini-player pause control did not produce a settled paused snapshot before the
  fixture reached the `1:00 / -0:00` end state.

## Gap

The local seed needs audio duration consistent with the `5m` metadata, or a
separate deterministic fixture for adjacent pause/resume validation.
