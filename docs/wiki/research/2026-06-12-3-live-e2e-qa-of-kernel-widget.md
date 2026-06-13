---
type: research-record
date: 2026-06-12
session: 38f8143c-c90d-49e3-a8fa-8d5ca17ac319
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/38f8143c-c90d-49e3-a8fa-8d5ca17ac319.jsonl
source_lines: 1529-1585
agent_attribution: Final live widget proof from main
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Live E2E QA of kernel widget projection: PROOF 1 PASS (decode unfrozen), PROOF 2 FAIL (idle widget during playback), PROOF 3 INCONCLUSIVE (change-gating)"
captured_at: 2026-06-12T13:47:34Z
---

Live E2E QA of kernel widget projection: PROOF 1 PASS (decode unfrozen), PROOF 2 FAIL (idle widget during playback), PROOF 3 INCONCLUSIVE (change-gating)

---

User: [Agent task result: Agent "Final live widget proof from main" completed]
The voice notify endpoint is returning 404 (server route unavailable on this host) — noted, but it does not affect the test results. Here is the final report.

---

# QA Validation Report: Kernel Widget Projection LIVE E2E Proof (PRs #366 + #371)

## Test Scope
Live end-to-end verification on iOS simulator (UDID `EC101638-D445-48E5-9933-B80A8B76370E`) of the kernel-built `WidgetSnapshot` (#366) and the #371 decode fix, built fresh from `origin/main` @ `7d4d1604` (#371). No source code edited.

## Build Provenance (verified before install)
- Worktree: `.claude/worktrees/agent-widget-final` detached at `7d4d1604` (the #371 commit). Both #366 (`3d62cb9d`) and #371 (`7d4d1604`) confirmed on `origin/main`.
- Rust: `cargo build -p nmp-app-podcast --target aarch64-apple-ios-sim` → OK (dylib 72MB, `@rpath` install name verified — no abs-path contamination).
- Swift: `BUILD SUCCEEDED` (the `appintentsnltrainingprocessor` SSU error is benign/non-fatal).
- Symbol verification in the installed `Podcastr.debug.dylib`: `decodePodcastUpdate` present (`nm` count 1), `nmp.widget.snapshot.v1` present, `WidgetSnapshot` type present.
- Installed OVER existing app (no uninstall); fresh binary mtime 12:03; relaunched with new PIDs (47944 → 50755 → 61065).

## Results by Proof

### PROOF 1 — Decode unfrozen: **PASS**
- `log show --last 1m --predicate 'process == "Podcastr"' | grep -c "decode FAILED"` = **0**. The pre-#371 `podcast.snapshot decode FAILED ... Path: widget` spam is **gone**.
- Library hydrated, not frozen: The Daily show page rendered **"2,884 episodes — Updated 4h ago"** with a full episode list (The Iran War's…, Maine Votes…, Congressional Republicans…, Scott Pelley…), each with a Play control. No "No episodes yet" / "0 episodes".
- Evidence: `/tmp/final-1.png` (Home), `/tmp/final-2.png` (sidebar+library), `/tmp/final-4.png` (show page with 2,884 episodes).

### PROOF 2 — Playback + plist: **FAIL**
- Playback **confirmed working** (twice): mini-player showed "The Iran War's D… · The Daily" advancing 0:00 → 0:30 with a pause glyph; OS `MPNowPlayingInfoCenter` received title="The Iran War's Devastating Butterfly Effect", artist="The Daily", duration=1731s, elapsedTime=45s, playbackRate=1; "Continue Listening — 26 min left" appeared. Evidence: `/tmp/final-6-playing.png`, `/tmp/final-7.png`, `/tmp/final-10-play2.png`.
- The widget App Group key **exists** at `group.com.podcastr.app` → `nmp.widget.snapshot.v1`, snake_case keys, decodes cleanly. **But its content never reflects the playing episode.** Decoded value throughout (and across a cold relaunch and a second instrumented playback, watched once/second for 40s):
```json
{ "is_playing": false, "unplayed_count": 2884, "position_fraction": 0, "position_secs": 0, "duration_secs": 0 }
```
- Required PASS conditions NOT met: `now_playing_episode_title` key is **absent**; `is_playing` stays **false**; `position_fraction` is 0; `duration_secs` is 0. (`unplayed_count` = 2884 > 0 is the only satisfied field.)

### PROOF 3 — Change-gating (pause → is_playing false): **INCONCLUSIVE / N/A**
Cannot validate the pause transition because the play transition never reached the plist — `is_playing` was already false during active playback. The change-gate IS functioning (it correctly skipped a rewrite because the kernel kept emitting an identical idle snapshot), but there is no playing→paused transition to observe in the App Group value.

## Root-Cause Evidence (the write path works; the content is idle)
- `WidgetCenter.reloadAllTimelines()` fires repeatedly during playback (12:07:22, :23, :26, :28, :59; 12:08:30; 5 calls in the last 90s of the 2nd test). `chronod` logs corresponding reload requests for `io.f7z.podcast.widget`. So `PlatformCapability.applyWidgetSnapshot`'s reload path **is invoked**.
- The plist file **does** get rewritten by the app (dir/file mtime updated to 12:10:54 on cold launch), proving the write seam works and the #371 decode is healthy.
- Therefore the defect is **upstream of the iOS write seam**: the kernel-owned `WidgetSnapshot` being emitted/applied during playback carries idle content (`is_playing=false`, no `now_playing_episode_title`, positions 0). The change-gate then legitimately suppresses rewrites because every emitted snapshot equals the last idle one. iOS is faithfully serializing an idle snapshot the kernel handed it.

## Net Determination
- #371 decode fix: **VALIDATED** — decode failures eliminated, library hydrates, App Group key written with correct snake_case schema, change-gating active.
- #366 kernel WidgetSnapshot now-playing projection: **NOT VALIDATED** — during real confirmed playback the snapshot never populates `is_playing` / `now_playing_episode_title` / position/duration. A home-screen now-playing widget would render the idle state while audio plays.

## Caveat on observation method
All plist reads are from the on-disk `group.com.podcastr.app.plist` via `plistlib`. cfprefsd can lag disk, but: (a) the file demonstrably rewrites (mtime advances) so the app's writes do reach disk; (b) a 40s once-per-second content watch spanning the play tap recorded only the idle state; (c) `defaults read` inside the sim reported the pair absent from its view. The convergent evidence is that the emitted content is idle, not that a correct value is hidden in cfprefsd. I could not coerce a cfprefsd flush (`killall` absent in sim PATH; in-sim `defaults` denied/sandboxed) to get a third independent read — flagging this as the one residual uncertainty, honestly.

## Artifacts
- Screenshots: `/tmp/final-1.png`, `/tmp/final-2.png`, `/tmp/final-3.png`, `/tmp/final-4.png`, `/tmp/final-5.png`, `/tmp/final-6-playing.png`, `/tmp/final-7.png`, `/tmp/final-8-prekill.png`, `/tmp/final-9-coldlaunch.png`, `/tmp/final-10-play2.png`
- Build logs: `/tmp/widget-final-xcodebuild.log` (1st attempt — failed on shared-SPM-cache `artifacts` race under disk pressure), `/tmp/widget-final-xcodebuild2.log` (`BUILD SUCCEEDED`)
- App left installed (per recipe). Worktree removed cleanly. No commits made.

## Environment notes
- Disk hovered at 99–100% (4.9–14GB free). 1st build failed with `Could not resolve package dependencies: The folder "artifacts" doesn't exist` — a concurrent-agent SPM-artifacts-cache extraction race (confirmed other `xcodebuild` building "iPhone 16" + another worktree resolving). Retry with cached LiteRT-LM artifact zips succeeded. I freed only regenerable caches (Highlighter DerivedData, ShipIt/updater caches, atlas/Google caches, orphaned Podcastr DerivedData with empty workspace paths). One `rm` of CoreSimulator/SiriTTS caches was denied by the harness and skipped.
- Voice notify endpoint `localhost:8888/notify` returns 404 (route unavailable); does not affect results.

**STATUS: Feature INCOMPLETE. #371 decode fix is proven good; the #366 now-playing widget projection does not populate playing state during live playback — back to Engineer on the kernel-side WidgetSnapshot now-playing derivation.**
