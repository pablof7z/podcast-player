# BDD Catalog 02 - Playback, Downloads, Transcripts, Clips

## Playback

| ID | Scenario | Evidence |
|---|---|---|
| PLAY-001 | Given a seeded episode is not playing, when Play is tapped, then playback starts, mini-player appears, and elapsed time advances. | SS: detail, mini-player, full player; Perf: tap-to-pause UI under 3 sec; Deps: UITestSeed audio; Boundary: D7,D8. |
| PLAY-002 | Given an episode is playing, when Pause is tapped, then audio pauses and elapsed time stops advancing. | SS: full player before/after; Perf: pause response under 250 ms; Deps: UITestSeed audio; Boundary: D4,D7. |
| PLAY-003 | Given playback is paused at T, when Play is tapped, then playback resumes near T instead of restarting. | SS: elapsed labels; Perf: resume under 1 sec; Deps: UITestSeed audio; Boundary: D4. |
| PLAY-004 | Given playback is active, when skip forward is tapped, then position advances by configured interval within tolerance. | SS: elapsed labels; Perf: action under 250 ms; Deps: seeded player; Boundary: D4,D7. |
| PLAY-005 | Given playback is active after 30 sec, when skip back is tapped, then position decreases by configured interval without pausing. | SS: elapsed labels; Perf: action under 250 ms; Deps: seeded player; Boundary: D4,D7. |
| PLAY-006 | Given an episode has chapters, when chapter skip is invoked, then the active chapter changes and position seeks to chapter boundary. | SS: chapter list and elapsed; Perf: seek under 500 ms; Deps: chapter seed; Boundary: D4,D7. |
| PLAY-007 | Given the scrubber is dragged to the midpoint, when released, then elapsed label, slider position, and audio position align. | SS: scrubber before/after; Perf: seek settle under 500 ms; Deps: seeded player; Boundary: D4,D7. |
| PLAY-008 | Given playback speed is changed to 1.5x, when 4 wall-clock seconds pass, then elapsed time advances about 6 seconds. | SS: speed sheet and elapsed labels; Perf: measured rate; Deps: seeded player; Boundary: D4,D7. |
| PLAY-009 | Given speed is changed, when app relaunches and playback starts, then saved speed is applied from Rust-owned settings. | SS: speed label after relaunch; Perf: none; Deps: preserved state; Boundary: D4. |
| PLAY-010 | Given a sleep timer is set for 5 minutes, when timer state projects, then player shows countdown and clears on cancellation. | SS: sleep sheet and player; Perf: injected clock update cadence; Deps: replay clock; Boundary: D4,D9. |
| PLAY-011 | Given sleep timer is set to end of episode, when playback reaches the final seconds, then audio stops and timer clears. | SS: final player state; Perf: stop within 1 sec of end; Deps: short audio fixture and replay clock; Boundary: D4,D9. |
| PLAY-012 | Given preroll ad metadata overlaps playhead, when skip ad appears and is tapped, then position jumps to content start. | SS: ad skip button and elapsed labels; Perf: skip under 250 ms; Deps: ad segment seed; Boundary: D4,D7. |
| PLAY-013 | Given auto-skip ads is enabled, when playback enters a known ad range, then playhead skips without visible loops. | SS: setting and elapsed jump; Perf: no repeated seeks; Deps: ad segment seed; Boundary: D4,D8. |
| PLAY-014 | Given the app backgrounds during playback, when foregrounded, then audio continues and full player resumes current state. | SS: foreground player; Perf: no interruption gap over threshold; Deps: seeded player; Boundary: D4,D7. |
| PLAY-015 | Given the app is force quit during playback, when relaunched, then episode detail shows resume at persisted position. | SS: relaunch episode detail; Perf: none; Deps: UITestSeedRelaunch; Boundary: D4. |
| PLAY-016 | Given Control Center sends pause/play, when remote commands fire, then kernel playback state updates and UI follows. | SS: app after remote command; Perf: command latency; Deps: remote command harness; Boundary: D7. |

## Queue And Downloads

| ID | Scenario | Evidence |
|---|---|---|
| QD-001 | Given two episodes exist, when Add to Queue is tapped, then the episode appears in Up Next from the kernel queue projection. | SS: queue sheet; Perf: update under 500 ms; Deps: UITestSeed; Boundary: D4,D5. |
| QD-002 | Given queue has three episodes, when an item is moved to top, then order changes and persists through relaunch. | SS: queue before/after/relaunch; Perf: reorder under 500 ms; Deps: queue seed; Boundary: D4. |
| QD-003 | Given queue has items, when one is removed, then it disappears and current playback is unaffected. | SS: queue and player; Perf: none; Deps: queue seed; Boundary: D4. |
| QD-004 | Given queue ends, when current episode finishes, then next queued episode starts automatically if auto-play is enabled. | SS: episode change; Perf: transition gap; Deps: short audio queue seed; Boundary: D4,D9. |
| QD-005 | Given auto-play is disabled, when current episode finishes, then no next episode starts and queue remains intact. | SS: ended state and queue; Perf: none; Deps: short audio queue seed; Boundary: D4. |
| QD-006 | Given a streamable episode, when Download is tapped, then progress appears and reaches downloaded state. | SS: progress and downloaded badge; Perf: progress cadence <= 1 Hz UI; Deps: download capability mock; Boundary: D5,D7,D8. |
| QD-007 | Given download is active, when network drops, then failed/paused state appears with retry and no crash. | SS: failure state; Perf: no retry loop storm; Deps: network failure cassette; Boundary: D6,D7,D8. |
| QD-008 | Given a failed download, when Retry is tapped, then a new capability request starts and progress resumes from policy. | SS: retry and progress; Perf: none; Deps: download replay; Boundary: D7. |
| QD-009 | Given a download is active, when Cancel is tapped, then capability stop is idempotent and item returns to not downloaded. | SS: cancel state; Perf: cancel under 500 ms; Deps: download mock; Boundary: D7,D8. |
| QD-010 | Given an episode is downloaded, when Delete Download is tapped, then file storage is reclaimed and episode remains in library. | SS: storage before/after; Perf: storage projection update; Deps: downloaded seed; Boundary: D4,D5,D7. |
| QD-011 | Given Wi-Fi-only downloads are enabled, when network is cellular, then auto-download queues but does not start. | SS: queued state; Perf: none; Deps: network capability mock; Boundary: D7. |
| QD-012 | Given storage limit is exceeded, when auto-download policy evaluates, then older eligible files are deleted by Rust policy, not native UI. | SS: storage screen; Perf: cleanup timing; Deps: storage seed; Boundary: D4,D7. |
| QD-013 | Given downloads screen is open, when a background progress event arrives, then only the download projection updates and no full library jank occurs. | SS: downloads screen; Perf: frame hitch and projection bytes; Deps: progress replay; Boundary: D5,D8. |
| QD-014 | Given multiple downloads run, when app backgrounds, then Live Activity/widget surfaces show bounded summary data only. | SS: widget/Live Activity; Perf: update cadence; Deps: download mock; Boundary: D5,D7,D8. |
| QD-015 | Given a local file is missing for a downloaded episode, when playback starts, then state falls back to stream or error according to Rust policy. | SS: error/fallback state; Perf: none; Deps: missing file fixture; Boundary: D6,D7. |
| QD-016 | Given an episode has a private feed token URL, when downloaded, then token is not exposed in screenshots, logs, or normal snapshots. | SS: redacted diagnostics; Perf: none; Deps: private feed cassette; Boundary: D5,D10. |

## Transcripts

| ID | Scenario | Evidence |
|---|---|---|
| TR-001 | Given a publisher VTT transcript is listed in RSS, when episode detail opens, then transcript CTA and segments render. | SS: transcript view; Perf: parse under 1 sec; Deps: RSS VTT cassette; Boundary: D4,D5. |
| TR-002 | Given a publisher SRT transcript is listed, when loaded, then timing and segment text render correctly. | SS: transcript segments; Perf: parse under 1 sec; Deps: SRT cassette; Boundary: D4. |
| TR-003 | Given a Podcasting 2.0 JSON transcript is listed, when loaded, then speaker/timing fields map to transcript state. | SS: transcript with speaker labels; Perf: parse under 1 sec; Deps: JSON transcript cassette; Boundary: D4. |
| TR-004 | Given transcript fetch returns unsupported MIME, when ingest runs, then graceful unsupported state appears. | SS: unsupported state; Perf: none; Deps: transcript HTTP cassette; Boundary: D6,D7. |
| TR-005 | Given no publisher transcript exists and OpenRouter Whisper is configured, when Generate Transcript is tapped, then STT request is routed through Rust and replayable. | SS: generate state and transcript; Perf: STT duration; Deps: `cassettes/stt/openrouter-whisper-basic.json`; Boundary: D7. |
| TR-006 | Given OpenRouter key is missing, when Whisper fallback is requested, then missing credential state appears from shared provider policy. | SS: provider error; Perf: none; Deps: no key fixture; Boundary: D6,D7. |
| TR-007 | Given ElevenLabs Scribe is selected, when transcript generation runs, then selected model and result are captured in a Scribe cassette. | SS: progress and transcript; Perf: STT duration and cost; Deps: `cassettes/stt/elevenlabs-scribe-basic.json`; Boundary: D7. |
| TR-008 | Given AssemblyAI is selected, when transcript generation runs, then submit/poll result is replayed from cassette with injected clock. | SS: progress states; Perf: poll count and duration; Deps: `cassettes/stt/assemblyai-submit-poll.json`; Boundary: D7,D9. |
| TR-009 | Given Apple on-device STT is selected, when permission is denied, then the app shows recoverable permission state. | SS: permission prompt and denied state; Perf: none; Deps: simulator permission state; Boundary: D6,D7. |
| TR-010 | Given transcript generation is in progress, when the user leaves episode detail, then progress continues or cancels according to kernel state and is visible on return. | SS: progress before/after navigation; Perf: no polling loop; Deps: STT replay clock; Boundary: D4,D8. |
| TR-011 | Given transcript segments are visible, when a segment is tapped, then playback seeks to that segment timestamp. | SS: segment and elapsed label; Perf: seek under 500 ms; Deps: transcript seed; Boundary: D4,D7. |
| TR-012 | Given transcript search finds a phrase, when result is tapped, then the transcript opens at the matching segment. | SS: search result and transcript; Perf: search under 500 ms; Deps: transcript index seed; Boundary: D5,D8. |
| TR-013 | Given transcript contains low-confidence regions, when displayed, then uncertainty is visible and not silently hidden. | SS: confidence styling; Perf: none; Deps: low confidence transcript fixture; Boundary: D1,D4. |
| TR-014 | Given a five-hour episode transcript, when scrolled rapidly, then virtualization preserves scroll performance and active line correctness. | SS: top/middle/end; Perf: scroll FPS and memory; Deps: long transcript seed; Boundary: D5,D8. |
| TR-015 | Given active playback with transcript follow-along, when the user scrolls away, then auto-scroll pauses and returns only on explicit action. | SS: manual scroll and return control; Perf: update cadence <= 60 Hz; Deps: transcript seed; Boundary: D8. |
| TR-016 | Given transcript ingest writes knowledge index entries, when app relaunches, then transcript search works without refetching provider data. | SS: search after relaunch; Perf: local search latency; Deps: transcript ingest replay; Boundary: D4,D5. |

## Clips, Highlights, And Sharing

| ID | Scenario | Evidence |
|---|---|---|
| CLIP-001 | Given a transcript segment is long-pressed, when Create Clip is tapped, then clip composer opens with sentence-snapped bounds. | SS: composer bounds; Perf: open under 500 ms; Deps: transcript seed; Boundary: D4. |
| CLIP-002 | Given clip handles are dragged, when released near sentence edges, then boundaries snap to transcript utterances. | SS: handles before/after; Perf: none; Deps: transcript seed; Boundary: D4. |
| CLIP-003 | Given no transcript exists, when AutoSnip is tapped, then the app either blocks publishing or uses a documented fallback without false context. | SS: AutoSnip result; Perf: none; Deps: no-transcript seed; Boundary: D6,D10. |
| CLIP-004 | Given playback is active, when AutoSnip creates a 30-sec clip, then stored bounds refine to meaningful utterance edges when transcript exists. | SS: clip row and bounds; Perf: creation under 1 sec; Deps: transcript seed; Boundary: D4,D5. |
| CLIP-005 | Given a user-created clip is saved, when Clippings opens, then it appears with caption, episode, show, and timestamp. | SS: composer and Clippings row; Perf: projection update under 500 ms; Deps: transcript seed; Boundary: D4,D5. |
| CLIP-006 | Given an agent-created clip is saved, when Clippings opens, then source badge identifies `.agent` and includes tool provenance. | SS: agent badge and provenance; Perf: none; Deps: LLM tool cassette; Boundary: D4,D7. |
| CLIP-007 | Given a clip is deleted, when confirmed, then it disappears from Clippings and related episode marks update. | SS: delete flow and list; Perf: update under 500 ms; Deps: clip seed; Boundary: D4. |
| CLIP-008 | Given a clip is shared as image, when share sheet opens, then generated card includes title, show, timestamp, and safe text layout. | SS: share preview; Perf: image render time; Deps: clip seed; Boundary: native render. |
| CLIP-009 | Given a clip is shared as audio, when export completes, then media file uses selected in/out bounds and excludes unrelated audio. | SS: export confirmation; Perf: export time; Deps: audio fixture; Boundary: D7. |
| CLIP-010 | Given a clip publishes to NIP-84 kind:9802, when relay accepts it, then raw event tags include `i`, `context`, and `alt` with no `a` tag. | SS: published state; Perf: relay ack timing; Deps: fixture relay plus nak replay; Boundary: D3,D7,D10. |
| CLIP-011 | Given relay rejects a clip publish, when ACK indicates failure, then publish state shows retry and local clip remains. | SS: failed state; Perf: none; Deps: relay reject cassette; Boundary: D6,D7. |
| CLIP-012 | Given clip content has unsafe markup, when quote card renders, then text is escaped and no layout overlap occurs. | SS: quote card; Perf: render time; Deps: unsafe text seed; Boundary: native render. |
| CLIP-013 | Given clip list has Today, This Week, and Earlier clips, when Clippings opens, then grouping is stable and date buckets use injected time. | SS: grouped list; Perf: none; Deps: replay clock; Boundary: D4,D9. |
| CLIP-014 | Given a clip deep link is opened cold, when app launches, then clip detail opens and can jump to source episode. | SS: cold deep link; Perf: route under 2 sec after snapshot; Deps: deep-link fixture; Boundary: D4,D5. |
| CLIP-015 | Given an orphan clip references a missing episode, when Clippings opens, then it shows recoverable orphan state without crashing. | SS: orphan row; Perf: none; Deps: UITestSeedOrphanClip; Boundary: D6. |
| CLIP-016 | Given a user edits clip caption, when saved and relaunches, then updated caption persists and publish metadata updates only through kernel action. | SS: edit and relaunch; Perf: none; Deps: clip seed; Boundary: D4,D7. |

