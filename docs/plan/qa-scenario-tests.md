# Pod0 iOS — QA Scenario Test Plan

**App:** Pod0 (`io.f7z.podcast`) — Nostr + AI podcast player
**Target device:** Physical iPhone 17 Pro Max, iOS 26.6
**Execution:** Automated UI driving (idb / maestro / XCUITest — TBD), on-device models (Gemma 4 local + Ollama/cloud fallback)
**Standard:** Zero technical debt. Anything that claims to work but doesn't, or is janky/slow, is a defect. Every PASS requires BOTH the observable criterion AND the performance criterion to hold.

> Scope: this plan validates the **feature contract** derived from `App/Resources/whats-new.json` and the live app surfaces (tabs: Home / Library / Bookmarks / Clippings / Wiki; toolbar: sidebar, Search, Agent, Settings). It supersedes nothing in `test-scenarios.json` — it is the higher-altitude journey layer above those atomic cases. Link from `docs/plan.md`.

---

## Execution notes (read first)

### How to drive the device
- Launch/relaunch, tap, type, swipe, screenshot via the `mcp__xcode__*` device tools (`launch_app_device`, `tap`, `type_text`, `swipe`, `gesture`, `long_press`, `screenshot`, `describe_ui`, `button` for hardware buttons).
- Bundle ID is **`io.f7z.podcast`** (NOT `com.podcastr.app`, which is the App Group).
- Build/install with `-skipPackagePluginValidation` in `extraArgs` (secp256k1 SharedSourcesPlugin trust). Run `tuist generate` first if project shape changed.
- Prefer `describe_ui` over screenshot-OCR for element existence/state; use screenshots only for visual/timing/jank evidence.

### How to MEASURE performance (never assume)
1. **Device log signposts (authoritative for latency).** Start a device log capture (`start_device_log_cap`) before the scenario; filter for the app's `os_signpost` / `PerfSignposter` marks (see `App/Sources/Bridge/PerfSignposter.swift`) and kernel rev-bump logs. Latency = signpost interval. This is the primary timing source for cold-launch, snapshot-decode, tap-to-action.
2. **Screenshot stopwatch (fallback / visual).** Capture timestamped screenshots in a tight loop (≤100ms cadence) bracketing the action; latency = (first frame showing target state) − (frame showing the tap). Use ONLY when no signpost exists.
3. **Scroll smoothness / jank.** Record device video (`record_sim_video` equivalent for device, or screen recording) during the gesture; inspect for dropped-frame stutter. Authoritative: capture Core Animation `commit` / hitch signposts via Instruments-style log; a hitch >2 frames (>33ms at 120Hz ProMotion, the panel runs 120Hz) during scroll is a FAIL. Visual fallback: frame-by-frame review of the recording for visible stutter.
4. **Main-thread blocking.** AI / kernel work must NOT freeze the UI. Test: while the AI task runs, drive a continuous scroll or tap a control every 200ms; if the UI stops responding to input for >150ms the task is blocking the main thread → FAIL regardless of correctness. Corroborate with hang-detection signposts in the log (`MetricKit`/hang markers).
5. **Numbers are budgets on a flagship (A19 Pro, 120Hz ProMotion, NVMe).** Each scenario justifies its budget inline. ProMotion means frame budget is **8.3ms**; "smooth" = sustained ≥118fps with no hitch >2 frames.

### Real data over mocks
- Use REAL podcast feeds (e.g. *This American Life*, *The Daily*) via iTunes search, and REAL Nostr (`relay.primal.net`) for discovery/social.
- Use REAL on-device Gemma 4 models for local-AI scenarios; cloud (Ollama / OpenRouter) only where the scenario explicitly tests fallback.
- A fresh-install baseline run (clean container) is required for onboarding/persistence scenarios; record the install timestamp.

### manual-assist scenarios
Flagged `[MANUAL-ASSIST]` need hardware or a second device that automation cannot fully drive: **lock screen / Control Center, Dynamic Island / Live Activity, CarPlay, AirPlay, handoff to iPad/Mac, headphone gestures, remote-signer QR bunker, real push notification delivery.** The executor drives everything it can and a human confirms the hardware-side observable. Pass criteria are still fully specified.

### Pass/Fail recording
For each scenario record: result (PASS/FAIL/BLOCKED), measured numbers vs budget, screenshot/video artifact paths, and for any FAIL a one-line defect description. Zero-debt rule: a janky-but-functional result is a FAIL, filed as a perf defect.

---

# P0 — Core promised journeys (MUST work for the app to be credible)

These ten are the credibility floor. If any P0 fails, the app does not meet its promise.

## P0-01 — Cold launch to interactive
**Feature(s):** App lifecycle, library survives restart, snapshot projection.
**Steps:**
1. Force-quit the app. Clear it from the app switcher.
2. Start device log capture.
3. Tap the app icon (or `launch_app_device`); start the stopwatch at launch intent.
4. Wait until Home is interactive: a tap on a Home element registers and content (subscriptions / Today) is rendered, not a spinner/skeleton.
**Observable pass:** Home renders real content (not just chrome/skeleton); first tap is accepted; no crash; previously-subscribed shows are present (persisted across restart).
**Performance:** Cold launch → interactive **< 2.0s**; warm launch **< 0.8s**. *Justification:* flagship NVMe + on-launch kernel snapshot decode; >2s on an A19 Pro for a local-first app indicates a main-thread decode or sync I/O stall (see `perf_snapshot_decode_hotpath`). Also assert: first kernel snapshot decode signpost **< 400ms** and runs off the main thread.

## P0-02 — Subscribe via iTunes search → appears reactively in library
**Feature(s):** iTunes search subscribe, reactive state (no manual refresh), library persistence.
**Steps:**
1. Tap Search (toolbar). Type `This American Life`. Submit.
2. Wait for results. Tap the first matching show.
3. On show detail, tap Subscribe.
4. Navigate to Library tab. Then force-quit and relaunch; return to Library.
**Observable pass:** ≥1 result with title+artwork; Subscribe toggles to subscribed state **immediately with no manual refresh** (reactive); show appears in Library without reload; subscription count +1; **survives restart**.
**Performance:** First search results visible **< 800ms** after submit (network-bound; budget assumes warm relay/iTunes, retry once before failing). Subscribe→library-reflect **< 300ms** (local kernel write + push frame). *Justification:* reactive seam must propagate within one frame budget cycle; >300ms implies a poll, not a push (see `project_podcast_projection_must_use_push_seam`).

## P0-03 — Tap episode → audio starts (tap-to-audio latency)
**Feature(s):** Core playback start, mini-player, now-playing.
**Steps:**
1. From a subscribed show with downloaded-or-streamable episodes, tap an episode's Play.
2. Observe mini-player appear and audio begin. Confirm audible output (or signpost that the audio engine started rendering).
**Observable pass:** Mini-player appears with correct title/artwork; audio is audibly playing within budget; scrubber advances; pause/play toggles correctly.
**Performance:** Tap → audio-start (streaming) **< 1.5s**; tap → audio-start (already downloaded) **< 0.6s**. *Justification:* downloaded file is local decode only; streaming adds first-byte+buffer. >1.5s streaming or >0.6s local indicates a stall in the playback pipeline.

## P0-04 — Resume where you left off + saved position persists
**Feature(s):** Resume, saved position, auto-mark-played, lifecycle correctness.
**Steps:**
1. Play an episode for ~60s. Note the timestamp.
2. Pause. Force-quit the app. Relaunch.
3. Open the same episode (and check the Home "Continue Listening" / Resume card).
4. Tap Resume/Play.
**Observable pass:** Resume card shows the episode at the saved position (±2s); playback resumes from saved position, not 0; position is persisted across the restart. Playing to the end marks the episode played and (if configured) auto-advances.
**Performance:** Saved-position write must not stall pause (pause UI responds **< 100ms**). Resume card present on Home within the P0-01 launch budget. *Justification:* position persistence is a kernel write; a recent changelog fix covers lock-screen Play position saving — regression-sensitive.

## P0-05 — Download for offline → live progress → offline playback
**Feature(s):** Downloads, live progress (queued/active/paused/failed from Rust kernel), offline library, offline playback.
**Steps:**
1. Trigger download on an episode. Observe the progress badge.
2. Watch state transitions: queued → active (progress climbs **live**, not stuck at 0%) → completed.
3. Enable Airplane Mode (or toggle network off).
4. Open the downloaded episode and play it; browse the offline library.
**Observable pass:** Progress advances live and monotonically (no stuck-at-0%); state labels reflect kernel states; downloaded episode plays fully **with no network**; offline library remains browsable. Pause/resume of a download produces correct paused/active states; a forced failure surfaces a failed state.
**Performance:** Progress UI updates **≥ 2 Hz** while downloading (live, per changelog fix); offline tap-to-audio **< 0.6s** (local). *Justification:* "stuck at 0%" was a real defect — liveness is the contract.

## P0-06 — Background playback continues
**Feature(s):** Background audio, audio session, lock-screen continuity.
**Steps:**
1. Start playback.
2. Press Home / lock the device (hardware `button`). Wait 60s.
3. Confirm audio continues. `[MANUAL-ASSIST]` confirm lock-screen controls + metadata.
4. Reopen the app.
**Observable pass:** Audio plays uninterrupted through backgrounding and screen-lock (changelog: "audio no longer cuts out when the screen locks"); on reopen the player shows the correct advanced position. Lock-screen shows title/artwork/scrubber and controls work `[MANUAL-ASSIST]`.
**Performance:** Zero audio dropouts during the 60s window; reopen → UI reflects live position **< 200ms**. *Justification:* any dropout is an immediate FAIL; this is a previously-regressed path.

## P0-07 — Library scroll stays smooth DURING playback
**Feature(s):** Reactive snapshot diffing off main thread, scroll perf under load.
**Steps:**
1. Start playback (mini-player active). Ensure a library with many episodes (subscribe to 5+ active shows; trigger 1–2 concurrent downloads to load the snapshot path).
2. Fast-scroll All Episodes / Library and a long show-detail episode list for ~10s while audio plays and a download progresses.
**Observable pass:** No visible stutter; mini-player keeps advancing; no dropped audio.
**Performance:** Sustained **≥ 118fps** (ProMotion 120Hz) with **no hitch > 2 frames (>16.6ms)** during the scroll; snapshot diff/decode runs **off the main thread** (changelog: "snapshot diffing now runs off the main thread"). *Justification:* every kernel rev-bump was a full JSON decode + O(N) hashing on main (`perf_snapshot_decode_hotpath`); this scenario is the regression guard.

## P0-08 — AI inbox triage prioritizes episodes without blocking the UI
**Feature(s):** AI inbox triage (background prioritization, score + categories, newest-first fallback), on-device model, main-thread safety.
**Steps:**
1. Ensure ≥1 local Gemma model is downloaded (see P0-10) OR cloud configured.
2. Have N ≈ 30 unread episodes across shows. Trigger / let inbox triage run (Home → Inbox).
3. While it runs, continuously scroll Home and tap a control every 200ms.
**Observable pass:** Inbox shows prioritized episodes with a visible score and category tags; ordering reflects triage; if the model is unavailable it falls back to **newest-first** (never empty/crash). UI stays fully responsive throughout.
**Performance:** Triage of N=30 completes **< 20s on-device** (Gemma 4 local) or **< 10s cloud**; **main thread never blocks > 150ms** at any point (corroborate with hang signposts). *Justification:* triage is background work by contract; any main-thread hang is a hard FAIL even if output is correct. Per-episode budget ~0.6s local is reasonable for a small on-device model.

## P0-09 — Sign in with Nostr key; key never leaves the kernel
**Feature(s):** Nostr sign-in (nsec), secure kernel key custody, identity surfaces.
**Steps:**
1. Onboarding / Identity → sign in with a test nsec.
2. Confirm the active account is set (avatar/npub shown).
3. Inspect: the key is held by the kernel and never surfaced to the Swift layer (changelog: "key is now held by the app's secure kernel and never leaves it"). Verify via Debug log / behavior — signing requests route through the kernel, app holds no raw nsec.
**Observable pass:** Account becomes active; npub/avatar render; subsequent signing (profile/feedback/comment publish) works **through the kernel**; the raw nsec is not stored in app-accessible state (no plaintext nsec in logs / Keychain dump under the app's own keys beyond the kernel custody store).
**Performance:** Sign-in → active account **< 1.5s**; first kernel sign round-trip **< 500ms**. *Justification:* custody is a security promise; correctness > speed but the round-trip must not feel broken.

## P0-10 — Local Gemma model download + on-device inference actually produces output
**Feature(s):** Local Gemma 4 models (private/offline), local LLM engine load + inference.
**Steps:**
1. Settings → AI → Local Models. Download a Gemma 4 model; watch progress.
2. After download, select it as the provider for a role (e.g. Agent / triage).
3. Trigger an inference that must use the local model (Airplane Mode ON to force offline) — e.g. ask the Agent a question, or run AI episode summary.
**Observable pass:** Model downloads with live progress; selecting it persists; an offline inference returns a **real, non-empty, on-topic** answer (NOT "model not loaded" / "not loaded" error, NOT a null/empty native return). Works with network OFF (private/offline promise).
**Performance:** Model download progress live ≥2Hz; first-token latency on-device **< 8s**; sustained generation **> 5 tok/s** for a 4B-class model on A19 Pro; engine load (warm) **< 3s**. *Justification:* offline inference is the headline promise.
> **KNOWN-RISK / ACTIVE REPAIR (2026-06-05):** the local engine-load path is currently unwired (`project_local_model_provider`) and on-device Gemma inference is failing — LiteRT-LM native `sendMessage` returns null — under active debugging by a concurrent session (the ad-hoc agent fallback is slated for removal). Until that fix lands, expect this scenario to FAIL on the inference step. **Run it as the acceptance gate for that repair:** it must flip to PASS (real on-device tokens, no null return, no silent fallback to cloud) before the local-model feature can be declared shipped. P0-08 / P1-23 / P1-25 / P1-24 local-model paths inherit this same risk — when forcing offline, a cloud fallback masking a dead local engine is itself a FAIL.

---

# P1 — Important features

## P1-11 — Full-screen now-playing: scrubber, speed, sleep timer
**Feature(s):** Now-playing, scrubber seek, speed up to 3.0x, sleep timer.
**Steps:** Open full player → drag scrubber to a new position → set speed to 3.0x → set a 5-min sleep timer.
**Observable pass:** Scrubber seek jumps audio to the dragged position; speed presets up to **3.0x** apply audibly and persist; sleep timer counts down and pauses at expiry.
**Performance:** Scrubber drag tracks finger at **≥118fps** (no lag); seek→audio-at-new-position **< 400ms**; speed change applies **< 150ms**.

## P1-12 — Skip forward/back with configurable intervals
**Feature(s):** Skip, configurable skip intervals.
**Steps:** Set custom skip intervals in Settings → Playback. Use skip-forward/back in player and via headphone/lock controls `[MANUAL-ASSIST]`.
**Observable pass:** Skip moves by exactly the configured interval; glyphs reflect the interval; setting persists across restart.
**Performance:** Skip → audio repositions **< 300ms**; control responds **< 100ms**.

## P1-13 — Auto-advance + auto-mark-played + auto-delete-after-played
**Feature(s):** Auto-advance, mark played, auto-delete after played.
**Steps:** Enable auto-delete-after-played and auto-advance. Play an episode to completion (seek near end).
**Observable pass:** On completion: episode marked played, next queued episode auto-advances and starts, the played download is auto-deleted (storage reflects the freed file).
**Performance:** Gap between episode end and next start **< 1.0s**.

## P1-14 — Pull-to-refresh + new-episode ingestion
**Feature(s):** Pull-to-refresh, feed refresh.
**Steps:** On a show with new episodes upstream, pull-to-refresh Library / show detail.
**Observable pass:** Refresh spinner shows then resolves; newly published episodes appear; no duplicates; existing state (downloads/played) preserved.
**Performance:** Refresh completes **< 3s** (network-bound, retry once); list update is non-blocking (scroll stays smooth).

## P1-15 — OPML import and export
**Feature(s):** OPML import/export.
**Steps:** Library/Settings → Import OPML (use a real OPML with 5+ feeds). Then Export OPML.
**Observable pass:** All feeds in the OPML get subscribed and appear in Library; export produces a valid OPML containing current subscriptions (round-trip identity for feed URLs).
**Performance:** Import of 10 feeds resolves **< 8s**; UI never blocks during import (progress visible, scroll responsive).

## P1-16 — Show detail: notes (HTML stripped), per-show auto-download (Wi-Fi-only)
**Feature(s):** Show detail, show notes HTML strip, per-show auto-download, Wi-Fi-only honored.
**Steps:** Open a show → view notes → enable per-show auto-download with Wi-Fi-only → simulate cellular (toggle Wi-Fi off, cellular on).
**Observable pass:** Notes render as clean text (no raw HTML tags); auto-download setting persists; on cellular with Wi-Fi-only ON, no auto-download starts; on Wi-Fi it does.
**Performance:** Show detail open → notes rendered **< 500ms**.

## P1-17 — All Episodes view + search within library
**Feature(s):** All Episodes view, in-library search.
**Steps:** Open All Episodes → type a query in search.
**Observable pass:** Combined cross-show episode list renders; search filters live and correctly; tapping a result opens the right episode.
**Performance:** Search results begin appearing **< 300ms** after keystroke (local filter); list scroll **≥118fps**.

## P1-18 — Downloads manager + free up space
**Feature(s):** Downloads manager, storage reclamation.
**Steps:** Settings → Downloads Manager. Review cached episodes and sizes. Delete one / clear.
**Observable pass:** Manager lists cached episodes with accurate sizes; delete removes the file and updates totals reactively; offline availability of deleted item is revoked.
**Performance:** Manager opens **< 500ms**; delete reflects **< 300ms**.

## P1-19 — Bookmarks / starred episodes
**Feature(s):** Bookmarks/starred (Bookmarks tab).
**Steps:** Star/bookmark an episode from a row context menu / swipe action → open Bookmarks tab → unbookmark.
**Observable pass:** Bookmarked episode appears in Bookmarks tab immediately (reactive); unbookmark removes it; survives restart.
**Performance:** Bookmark toggle reflects **< 200ms**.

## P1-20 — Clips: scissors + Auto Snip ±30s
**Feature(s):** Clips, Auto Snip, Clippings tab.
**Steps:** During playback, use scissors to create a clip; use Auto Snip (±30s). Open Clippings tab.
**Observable pass:** Clip created with correct in/out around the playhead; Auto Snip captures the ±30s window; clip appears in Clippings and is playable/shareable.
**Performance:** Clip creation reflects **< 1.0s**; Auto Snip extraction non-blocking.

## P1-21 — Transcripts: time-synced, tap-to-seek, on-device Apple Speech default
**Feature(s):** Transcripts (time-synced, tap-to-seek), on-device Apple Speech default + cloud fallback, background auto-transcribe.
**Steps:** Open an episode without a publisher transcript → let on-device transcription run → open transcript in player → tap a line.
**Observable pass:** Transcript generates (on-device Apple Speech by default); lines are time-synced and highlight with playback; **tap-to-seek** jumps audio to that line; long-press a line offers "ask the agent about that moment."
**Performance:** Tap-line → audio-at-line **< 400ms**; transcript scroll-follow keeps up at **≥118fps**; on-device transcription runs in background without blocking the UI (>150ms hang = FAIL).

## P1-22 — Chapters: publisher + AI-generated (sparkles badge)
**Feature(s):** Chapters (publisher + AI evenly-spaced w/ sparkles badge), CarPlay chapter readiness.
**Steps:** Episode with publisher chapters → verify list. Episode without → trigger AI chapter generation.
**Observable pass:** Publisher chapters list with titles/times; AI-generated chapters appear evenly-spaced with a **sparkles badge**; tapping a chapter seeks; chapters appear even if they arrive after playback start (changelog fix).
**Performance:** Chapter tap → seek **< 400ms**; AI chapter generation non-blocking; chapters render within **< 1.0s** of becoming ready.

## P1-23 — AI episode summary
**Feature(s):** AI episode summaries (on-device capable).
**Steps:** On an episode, request an AI summary (local model preferred).
**Observable pass:** A coherent, on-topic summary renders (non-empty, not an error); reflects the episode content/transcript.
**Performance:** Summary first content **< 12s** on-device; generation non-blocking (UI responsive throughout).

## P1-24 — For You / Recommended picks with reasons
**Feature(s):** "Recommended for you" / AI picks with reasons, read-aloud.
**Steps:** Open Home → Recommended / Agent Picks section.
**Observable pass:** Picks render with a per-item **reason**; tapping plays the episode; "read picks aloud and explain why" works (changelog). Falls back gracefully if model unavailable.
**Performance:** Picks section populates **< 5s** (cached/local); shimmer placeholder while loading, never an empty broken state.

## P1-25 — Agent chat tab: Q&A over the library
**Feature(s):** Agent chat, LLM client, conversation persistence.
**Steps:** Open Agent (toolbar). Ask a question about a subscribed show / recent episode. Start a new conversation; reopen history.
**Observable pass:** Agent returns a relevant, grounded answer (cites/uses library context); typing indicator shows during generation; conversation persists in history; unread-reply badge behaves.
**Performance:** First token **< 8s** (local) / **< 4s** (cloud); streaming visible; UI responsive during generation.

## P1-26 — Voice mode: spoken Q&A
**Feature(s):** Voice mode (spoken Q&A over library), speech recognition + TTS, barge-in.
**Steps:** Open Voice → speak a question → listen to spoken answer → barge in mid-answer.
**Observable pass:** Speech recognized (caption shown); spoken answer is relevant; barge-in interrupts TTS and starts listening; orb/visual state reflects listening/speaking.
**Performance:** End-of-speech → response speech start **< 3s**; barge-in interrupt **< 300ms**.

## P1-27 — AI Wiki per show
**Feature(s):** AI wiki per show, citations.
**Steps:** Open Wiki tab → generate/open a wiki page for a subscribed show → tap a citation chip.
**Observable pass:** Wiki page generates with coherent sections and **citation chips**; tapping a citation peeks the source; evidence grading present.
**Performance:** Wiki generation shows progress and first content **< 15s**; non-blocking.

## P1-28 — Episode comments via Nostr (publish + fetch)
**Feature(s):** Episode comments (Nostr), publish+fetch from device, kernel signing.
**Steps:** On an episode, open comments → post a comment → confirm it publishes to relay and appears; relaunch and confirm fetch.
**Observable pass:** Comment publishes (signed via kernel), appears in the thread, and is fetched fresh after relaunch (round-trips through `relay.primal.net`); reactive, no manual refresh.
**Performance:** Publish→appears **< 2s**; fetch on open **< 3s** (network, retry once).

## P1-29 — Social tab: live follow list with photos
**Feature(s):** Follow list / Social, live contacts + avatars.
**Steps:** Open Friends/Social → view follows with photos → open a friend detail.
**Observable pass:** Follow list renders with names + avatar photos (live from Nostr); friend detail loads profile; reactive (no polling — see `feedback_nostr_reactive`).
**Performance:** List first paint **< 2s**; avatar images load progressively without blocking scroll.

## P1-30 — Profile edit + publish + cross-device sync
**Feature(s):** Profile edit/publish, cross-device sync (kind-0).
**Steps:** Identity → Edit Profile → change name/bio/picture → save/publish. `[MANUAL-ASSIST]` confirm on a second device/client.
**Observable pass:** Edits publish (signed via kernel); local UI reflects immediately; a second device/client sees the updated kind-0 (changelog: profile syncs across devices).
**Performance:** Publish→local reflect **< 1s**; round-trip visible on relay **< 5s**.

## P1-31 — Settings sync via iCloud (default speed + auto-delete)
**Feature(s):** Default speed + auto-delete sync via iCloud.
**Steps:** Change default speed + auto-delete on device A. `[MANUAL-ASSIST]` observe sync to device B (or NSUbiquitousKeyValueStore round-trip).
**Observable pass:** Settings persist locally and propagate via iCloud KVS; second device reflects within sync latency.
**Performance:** Local persist **< 100ms**; iCloud propagation best-effort (≤ a few min) — not a hard latency FAIL, but data correctness is.

## P1-32 — Remote signer (NIP-46 bunker QR) sign-in
**Feature(s):** Remote signer QR bunker sign-in, kernel custody.
**Steps:** `[MANUAL-ASSIST]` Identity → Remote Signer / Nostr Connect → scan/paste a bunker URI → approve on the signer.
**Observable pass:** Connection establishes; account active without a local nsec; signing requests round-trip to the remote signer; key never on device.
**Performance:** Connect→active **< 5s**; sign round-trip **< 3s** (signer-dependent).

## P1-33 — OpenRouter / API-key onboarding to Keychain
**Feature(s):** OpenRouter/API key onboarding, Keychain storage, store_open_failure warning.
**Steps:** Onboarding AI setup or Settings → AI → enter an OpenRouter/API key → use a cloud model.
**Observable pass:** Key saved to Keychain (persists across restart, never shown in plaintext logs); cloud inference works with it; if Keychain open fails, the `store_open_failure` user warning is shown (don't silently swallow).
**Performance:** Key save **< 300ms**; first cloud inference unaffected beyond network.

## P1-34 — What's-New sheet surfaces new entries
**Feature(s):** What's-new changelog sheet.
**Steps:** Set last-seen marker behind the newest `whats-new.json` entry → relaunch.
**Observable pass:** What's-New sheet appears showing entries newer than the marker (and only those); dismissing advances the marker so it doesn't reappear.
**Performance:** Sheet presents within launch budget; no jank on scroll of entries.

## P1-35 — Debug log viewer
**Feature(s):** Debug log viewer (search/copy/clear).
**Steps:** Settings → Debug → enable debug logging → reproduce activity → search, copy, clear.
**Observable pass:** Log captures recent activity; search filters; copy works; clear empties it; toggling logging off stops capture.
**Performance:** Viewer opens **< 500ms**; search over a large log filters **< 300ms**, non-blocking.

## P1-36 — Notifications for new episodes
**Feature(s):** New-episode notifications.
**Steps:** `[MANUAL-ASSIST]` Settings → Notifications → enable → trigger a new episode on a subscribed feed → background the app.
**Observable pass:** A local/push notification fires for the new episode; tapping it deep-links to that episode.
**Performance:** Notification fires within the app's refresh window; deep-link open **< 2s**.

---

# P2 — Nice-to-have / breadth coverage

## P2-37 — Dynamic Island / Live Activity
**Feature(s):** Live Activity, Dynamic Island. `[MANUAL-ASSIST]`
**Steps:** Start playback → observe Dynamic Island compact + expanded; lock screen Live Activity.
**Observable pass:** Title/artwork/progress show; controls work; updates track playback. **Perf:** Live Activity updates ≥1Hz without lag.

## P2-38 — Control Center metadata + controls
**Feature(s):** Control Center now-playing. `[MANUAL-ASSIST]`
**Steps:** Play → open Control Center → use play/pause/skip.
**Observable pass:** Correct metadata + artwork; controls drive the player. **Perf:** control→audio response **< 300ms**.

## P2-39 — AirPlay route
**Feature(s):** AirPlay. `[MANUAL-ASSIST]`
**Steps:** Player → route picker → select an AirPlay target.
**Observable pass:** Audio routes to target; route picker reflects selection; playback continues. **Perf:** route switch **< 3s**.

## P2-40 — CarPlay: library + per-show + chapters + now-playing
**Feature(s):** CarPlay. `[MANUAL-ASSIST]` (CarPlay sim or head unit)
**Steps:** Connect CarPlay → browse Shows → open a show → play → open chapters → now-playing.
**Observable pass:** Library and per-show lists render; chapters list shows (even if chapters arrive post-start — changelog); now-playing controls work; downloads list available offline. **Perf:** list navigation **< 1s** per screen; no driver-distraction jank.

## P2-41 — Handoff iPhone ↔ iPad/Mac
**Feature(s):** Handoff. `[MANUAL-ASSIST]` (second device)
**Steps:** Play on iPhone → pick up on iPad/Mac via Handoff.
**Observable pass:** The other device offers the same episode at the same position; resumes correctly. **Perf:** handoff appears within Apple's continuity latency.

## P2-42 — Ad-skip: persisted detected segments
**Feature(s):** Ad-skip, persisted detected segments.
**Steps:** Play an episode with known/detected ad segments → reach a segment → relaunch and replay.
**Observable pass:** Detected ad segment is skippable / auto-skipped; the detection persists across restart (no re-detect needed). **Perf:** skip transition seamless (**< 500ms** gap).

## P2-43 — AI category tags on episodes
**Feature(s):** AI category tags (BM25 fallback).
**Steps:** Open episodes / Home category cards → verify category tags.
**Observable pass:** Episodes carry sensible AI category tags; category scoping/filter chips on Home work; BM25 fallback yields tags when the model is unavailable. **Perf:** categorization non-blocking; chip filter applies **< 200ms**.

## P2-44 — Subscribe via Nostr discovery (NIP-F4 / NIP-74)
**Feature(s):** Nostr podcast discovery + subscribe.
**Steps:** Search/Discover → a Nostr-discovered show (NIP-F4/74) → subscribe.
**Observable pass:** Nostr-discovered show subscribes and behaves like an RSS sub (episodes, playback). **Perf:** discovery results **< 3s** (relay, retry once).

## P2-45 — Agent-created / managed podcast with AI cover art
**Feature(s):** Agent-created podcasts, AI cover art, AI-generated narrated episodes.
**Steps:** Agent → create/manage a podcast → generate a short narrated episode → view AI cover art.
**Observable pass:** Agent creates a podcast entity with AI cover art; a short narrated AI episode is generated and **playable**; appears in library. **Perf:** narrated-episode generation shows progress; non-blocking; produces audible audio.

## P2-46 — NIP-65 relay config + app relays + agent relay
**Feature(s):** NIP-65 relay config, app relays, agent relay.
**Steps:** Settings → Networking → view/edit relays → run relay diagnostics.
**Observable pass:** Relay lists editable; NIP-65 published on change; diagnostics report reachability; agent relay configurable separately. **Perf:** diagnostics per-relay result streams in, non-blocking.

## P2-47 — Sidebar podcasts + See All
**Feature(s):** Sidebar quick access + See All.
**Steps:** Open sidebar (toolbar) → tap a podcast → tap See All.
**Observable pass:** Sidebar lists podcasts; tap navigates to the show; See All shows the full `AllPodcastsListView`. **Perf:** sidebar opens **< 200ms**; See All scroll **≥118fps**.

## P2-48 — Disk-full / store-open failure recovery
**Feature(s):** Disk-full recovery, store_open_failure warning, graceful degradation.
**Steps:** `[MANUAL-ASSIST]` Constrain storage (fill disk) → attempt a download / kernel write.
**Observable pass:** App surfaces a clear user warning (no silent failure, no crash); recovers when space is freed; no data corruption. **Perf:** failure surfaces promptly (**< 2s**), app remains responsive.

## P2-49 — Threaded Today / topic-pivot lenses on Home
**Feature(s):** Threaded Today pill, topic-pivot lenses.
**Steps:** Home → Today pill → pivot between angles/lenses on a story.
**Observable pass:** Threaded Today renders; pivoting changes the angle without leaving Home; content is coherent. **Perf:** pivot transition **< 500ms**; no jank.

## P2-50 — Long-press transcript line → ask agent about that moment
**Feature(s):** Transcript→agent deep context.
**Steps:** Player transcript → long-press a line → ask the agent.
**Observable pass:** Agent answers with that exact moment as context; returns to player cleanly. **Perf:** agent first token within P1-25 budget; long-press menu appears **< 150ms**.

---

## Coverage summary

| Priority | Count | Theme |
|---|---|---|
| **P0** | 10 | Subscribe, play, resume, download/offline, background, reactive scroll perf, AI inbox triage, local-model inference, kernel key custody, cold launch |
| **P1** | 26 | Player depth, transcripts, chapters, AI summary/picks/wiki/agent/voice, Nostr comments/social/profile/signer, OPML, downloads mgr, settings/debug/notifications |
| **P2** | 14 | Hardware/continuity (Dynamic Island, Control Center, AirPlay, CarPlay, Handoff), ad-skip, AI categories/agent podcasts, relay config, sidebar, failure recovery |
| **Total** | **50** | |

## Defect / zero-debt policy
A scenario PASSES only if BOTH its observable AND performance criteria hold. A correct-but-janky or correct-but-main-thread-blocking result is a FAIL filed as a perf defect. `[MANUAL-ASSIST]` scenarios that cannot be observed are BLOCKED, not PASSED. Every FAIL/BLOCKED gets a one-line defect entry routed to `docs/BACKLOG.md`.
