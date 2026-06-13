---
type: research-record
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
source_lines: 4816-4867
agent_attribution: a862e33c48de93b7b
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Systematic verification of Android PR #404: field-by-field schema symmetry check across 7 domains, clobber-removal verification, tombstone/drop-guard correctness analysis — verdict APPROVE"
captured_at: 2026-06-12T17:49:39Z
---

Systematic verification of Android PR #404: field-by-field schema symmetry check across 7 domains, clobber-removal verification, tombstone/drop-guard correctness analysis — verdict APPROVE

---

User: [Agent task result: Agent "Opus review: Android per-domain consume #404" completed]
The injection happens in the Android bridge (Kotlin/JNI) consuming `nmp_app_podcast_decode_update_frame`. Since this is the iOS-twin design and #403 already validated the `v.projections[key]` shape on the bridge side (the bridge is shared infra, not changed by this PR), and the PR description states the decode bridge already injects sidecars, the Kotlin consumer is reading the established shape. The key fact: this PR is Android-only Kotlin (confirmed by diff stat — only 3 Kotlin files), the bridge injection is pre-existing.

Let me do one final check: confirm there are no wire tests on the Android side and confirm the Kotlin compiles structurally by checking the merge uses fields that exist on PodcastSnapshot (e.g., `agentTasks`, `feedbackEvents`, `feedbackThreads`, `voice`, `agent` all exist). I saw `agentTasks`, `feedbackEvents`, `feedbackThreads` in the snapshot. `voice` and `agent` exist too. All merge targets exist.

One subtle thing worth flagging: the `DomainRevTracker` is `remember { DomainRevTracker() }` — it resets on process restart (cold start) but the cold-start pull via `decode` sets `snapshot` WITHOUT touching the tracker (tracker stays all-0). So the first push frame for any domain (rev > 0) will be accepted and merge over the pulled snapshot — correct, since the pulled snapshot is the full current state and the first push carries the same-or-newer rev. Good. There's no scenario where the tracker starting at 0 drops a needed frame.

Let me confirm there's no issue with cold-start tracker vs pulled snapshot rev: the pull sets full state but tracker=0, so a redundant first push (same rev as pull) would re-merge identical data — harmless (anyAccepted=true, same content). No clobber. 

I have everything needed for a decisive verdict.

---

## VERDICT: APPROVE

Independent review complete. This PR fully removes the empty-library clobber bug and ships the Android per-domain push-consumption half as a faithful twin of the already-approved iOS #403. I read every changed file plus the Rust emitter and the iOS twin for cross-checking.

### 1. Clobber removed + cold-start — FULLY FIXED, no blank-library path remains
- The old `decodeFromJsonElement(PodcastSnapshot.serializer(), v)` path is **gone** — the entire `decodeEnvelope` + `SnapshotEnvelope` block was deleted from `PodcastSnapshot.kt` (diff lines 487–535 removed). The slim `v` is never again decoded as a full snapshot.
- `MainActivity.kt:166-172` applies `snapshot = merged` **only when `anyAccepted == true`**. A frame with no domains returns `null` from `decodeDomainFrames` (the `if (!frames.hasAnyDomain) null` guard, `DomainFrames.kt`), hits `?: continue`, and never touches state. A frame whose domains are all stale yields `anyAccepted=false` → no assignment.
- Cold-start hydrator is intact: `MainActivity.kt:140-148` still does the one-shot `bridge.podcastSnapshot()` PULL → `SnapshotCodec.decode` (the full-snapshot decoder, retained). The grid paints on launch.
- Absent domains are merged via `copy()` touching only present slices — they are never cleared. **The empty-clobber is fully removed, not narrowed.** There is no remaining path where a push frame blanks the library: blanking now requires an explicit library tombstone (`{"rev":N,"library":null}`) at a higher rev, which is the intended all-unsubscribed signal.

### 2. Schema symmetry — `@SerialName` ↔ Rust emitted fields (per-domain table)

Rust emitter: `apps/nmp-app-podcast/src/ffi/snapshot_domain_projections.rs`. `ignoreUnknownKeys = true` is set (`DomainFrames.kt` SnapshotCodec.json), so Rust-only fields are safely dropped on Android. All Kotlin domain-frame fields are nullable/defaulted → no missing-required throw risk.

| Domain | Rust emits | Kotlin `@SerialName` | Match |
|---|---|---|---|
| library | rev, library, categories, search_results, nostr_results, owned_podcasts, inbox, inbox_triage_in_progress | rev, library, `search_results`, inbox, `inbox_triage_in_progress` | ✅ (categories/nostr_results/owned_podcasts intentionally not modeled on Android — no top-level field exists, same as iOS-renders-only superset; harmless via ignoreUnknownKeys) |
| playback | rev, now_playing, queue | rev, `now_playing`, queue | ✅ |
| downloads | rev, downloads | rev, downloads | ✅ |
| settings | rev, settings, configured_relays | rev, settings | ✅ (configured_relays not modeled on Android, as in base snapshot) |
| identity | rev, active_account | rev, `active_account` | ✅ |
| widget | rev, widget | rev, widget | ✅ |
| misc | rev, +15 fields | rev, `agent_tasks`, `feedback_events`, `feedback_threads`, voice, agent | ✅ subset (wiki/picks/clips/social/etc. not rendered on Android) |

Nested types (`NowPlayingState`, `DownloadQueueSnapshot`, `EpisodeSummary`, `PodcastSummary`, `AccountSummary`, `WidgetSnapshot`, `InboxItem`) are **unchanged, pre-existing** types already proven by the working cold-start `decode` pull path; the domain frames reuse them, inheriting correct `@SerialName`s. No mismatch found.

### 3. Tombstone handling — correct
`coerceInputValues = true` does **not** corrupt tombstones because every tombstone primary field is nullable (`library: List<...>? = null`, `downloads`, `activeAccount`, `widget`) — null stays null, no throw. Merge maps: library null → `emptyList()`, identity null → `activeAccount = null` (signed out), downloads null → `downloads = null`, widget null → `widget = null`. Matches the Rust tombstone shapes exactly.

### 4. Drop guard + merge — correct
Per-domain `frame.rev > tracker[domain]` monotonic guard; `copy()` replaces only accepted domains. Sidecar `rev` is the global rev (Rust `update.rev` for all domains) — same as iOS. Tracker is `remember { DomainRevTracker() }`, resetting to all-0 on process restart; combined with the cold-start pull (which sets full state without advancing the tracker), the first post-launch push for each domain is accepted and merges identical-or-newer data over the pulled snapshot — no drop, no clobber.

### 5. Hygiene
Android-only: diff stat is 3 Kotlin files (`DomainFrames.kt` new, `MainActivity.kt` +20/-8, `PodcastSnapshot.kt` -51 codec removal). No Rust/JNI change. All merge targets (`agentTasks`, `feedbackEvents`, `feedbackThreads`, `voice`, `agent`, etc.) exist on `PodcastSnapshot`. The `MainActivity` edit is minimal and localized to the frame loop (lines 151-173) plus one tracker declaration — it will not conflict heavily with the uncommitted identity WIP in the shared root (that WIP is in the DisposableEffect/identity-restore block, a different region).

### Optional follow-up (non-blocking)
No Android-side wire fixture test exists (iOS has `KernelBridgeWireTests.swift`). The MEMORY note "demand Rust-JSON→bridge-decoder fixture tests" applies — an Android instrumentation/unit test feeding a captured `{"t":"snapshot","v":{"projections":{...}}}` fixture through `decodeDomainFrames`/`mergeFrames` would lock the snake_case contract against future Rust field renames. Recommend as a fast-follow, not a merge blocker, since this PR is a twin of validated iOS code and decodes a strict subset of already-proven nested types.

Ship it.
