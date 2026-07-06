# Pod0 Evidence Pack - 2026-07-05

This directory contains current local validation evidence for the first
evidence-backed Pod0 scenario subset.

## Selected Scenarios

| Scenario | Verdict | Reason |
| --- | --- | --- |
| LIB-001 Subscribed show appears in Library | pass_with_issues | The seeded subscribed show appears with title/provider summary, episode count, artwork, and show-detail navigation. |
| PLAY-001 Play starts playback | pass_with_issues | Playback starts, the mini-player appears, and elapsed time advances; adjacent pause/resume validation is blocked by #718. |
| SET-001 Playback settings | incomplete | Playback settings and one toggle persistence path are captured; skip interval changes, player propagation, and relaunch persistence remain unvalidated. |
| SET-005 Storage breakdown | fail | Downloads reports one saved 240 KB episode while Downloads & Disk reports Zero KB in the same run. |

## Skill Grounding

Required search and selected skill:

```sh
npx skills search "iOS UI UX performance accessibility critique"
npx skills add yuniorglez/gemini-elite-core@ui-ux-specialist
```

Selected skill: `yuniorglez/gemini-elite-core@ui-ux-specialist`.

The critique below applies its WCAG 2.2 / inclusive-design priorities: target
size, visual clarity, predictable navigation, clear recovery, accessible state
labels, reduced cognitive load, and performance budgets. iOS simulator execution
uses the local `xcodebuildmcp-cli` workflow and XcodeBuildMCP UI snapshots.

## Run Context

- Worktree: `/Users/customer/Work/podcast-player-pod0-evidence-pack`
- Branch: `codex/pod0-evidence-validation-pack`
- Base source commit when app was built: `dd5a3d48a14f`
- Simulator: iPhone 17, iOS 26.2, UDID `B4E1F31A-044B-4860-860B-C325BE5CC36E`
- Launch args: `--UITestSeed`
- Build/run command: XcodeBuildMCP `build_run_sim` with `-skipPackagePluginValidation`
- Shared log reference: `assets/scenarios/shared/20260705T193205Z-run-log-references.json`

## Defects Filed

- https://github.com/pablof7z/podcast-player/issues/717
- https://github.com/pablof7z/podcast-player/issues/718

The `scenario-records/` JSON files are generator overlays; they do not replace
the BDD catalog. They attach current evidence to generated report records.
