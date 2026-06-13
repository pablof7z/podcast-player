---
type: research-record
date: 2026-06-12
session: c1691db0-d63e-4062-adad-1cfa0d679d09
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/c1691db0-d63e-4062-adad-1cfa0d679d09.jsonl
source_lines: 6401-6452
agent_attribution: ab5e17deadb32edad
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Structured evaluation of PR #418 Blossom upload; verdict REQUEST-CHANGES — orphaned BlossomUploaderTests.swift breaks test-target build, action_results shape match confirmed, registry race/leak correct, D13/D0 clean"
captured_at: 2026-06-12T22:27:14Z
---

Structured evaluation of PR #418 Blossom upload; verdict REQUEST-CHANGES — orphaned BlossomUploaderTests.swift breaks test-target build, action_results shape match confirmed, registry race/leak correct, D13/D0 clean

---

User: [Agent task result: Agent "Opus review: Blossom upload #418" completed]
Decisive confirmation. The test target globs `sources: ["AppTests/Sources/**"]` (Project.swift:210), so `AppTests/Sources/BlossomUploaderTests.swift` IS compiled into the `PodcastrTests` target. Since the PR deleted the production `BlossomUploader.swift` (the pbxproj diff shows the two `BlossomUploader.swift in Sources` build-file refs removed) but left the 260-line test referencing `BlossomUploader`/`BlossomUploadError.serverRejected`/`.malformedDescriptor` and the `(server:session:)` init + `upload(...:signer:)` method, **the test target will fail to compile.**

Note: `BlossomUploadError.serverRejected` and `.malformedDescriptor` are re-declared in the new `KernelModel+BlossomUpload.swift`, so those two cases still resolve — but `BlossomUploader` (the struct), its `(server:session:)` init, the `(serverURLString:)` init, the `upload(data:contentType:signer:)` method, and `BlossomUploading` are all gone. The test references those → compile failure.

I have a complete, decisive picture. Let me write the verdict.

---

## VERDICT: REQUEST-CHANGES

One concrete, build-breaking defect — the exact "deleted-file orphan" trap from focus #1. Everything else in the PR is correct and well-built; the fix is a one-file deletion.

### Process note (important)
The remote branch ref `feat/blossom-upload-via-nmp` is being **force-pushed by concurrent agents** — between my fetches it pointed at three different commits (a blossom commit, then an unrelated "FollowListProjection" commit `df07992b`). The authoritative PR #418 head per `gh` is **`7e4cd170`**; I pinned and reviewed that exact SHA. All findings below are against `7e4cd170...origin/main`.

---

### 1. Orphan check — ONE OFFENDER (build-breaking) ❌
- Production `App/Sources/Services/BlossomUploader.swift` correctly deleted (pbxproj build-file refs removed for both app + a second target).
- `KernelSigner` was **NOT** deleted (it lives in `App/Sources/Services/Nip46/NostrSigner.swift`, untouched) — the PR description was inaccurate there. It is now **dead code**, though: on `main` its only two constructors were the avatar + artwork sites, both converted here. Unused internal struct → compiles fine. Cosmetic, not blocking.
- **OFFENDER: `AppTests/Sources/BlossomUploaderTests.swift` (260 lines) is untouched by the PR and references the deleted symbols** — `BlossomUploader(server:session:)`, the `upload(data:contentType:signer:)` method, `BlossomUploading`. The test target globs `AppTests/Sources/**` (`Project.swift:210`), so this file compiles into `PodcastrTests` → **test target build fails.** The agent's "Swift build passed" was the app target only, not `build-for-testing`. This is precisely the recurring trap.

**Minimal fix:** delete `AppTests/Sources/BlossomUploaderTests.swift` (its HTTP-transport assertions are obsolete — transport moved to Rust, covered by `nmp-blossom`'s own tests). Optionally also delete the now-dead `KernelSigner` struct + the `BlossomUploadError.invalidResponse` case is already gone. After deletion, re-grep `BlossomUploader|BlossomUploading` across `App/`+`AppTests/` → must be zero.

### 2. action_results shape match — MATCH (for both current callers) ✅
Traced end-to-end against pinned nmp-core/nmp-blossom rev `4fdcb52`:
- Rust `ActionResultRow.result` is `Option<String>` = the **serialised JSON string** of the result body (`action_results_fb.rs:64-67`). Swift reads `row["result"] as? String` then `JSONSerialization`-decodes it to reach `obj["url"]` (`KernelModel+BlossomUpload.swift:108-116`). Nesting matches.
- The body itself: `nmp-blossom/src/upload/mod.rs` produces **two shapes** — single-server (line 269-275) = flat `BlobDescriptor` with **top-level `url`**; multi-server (line 283-297) = `{ sha256, size, type, uploaded, servers: [{server, ok, url}] }` with **NO top-level `url`**. Both converted call sites pass exactly one server (`[blossomServer]`, `[settings.blossomServerURL]`) → single-server flat shape → `obj["url"]` resolves. **Match confirmed.**
- Latent risk (not in this PR): any future caller passing >1 server would hit the nested shape and Swift's `obj["url"]` would be nil → `malformedDescriptor`. Worth a one-line follow-up note in `blossomUpload`.

### 3. Registry race/leak — CORRECT ✅
- Buffered-before-await and await-before-buffered both handled under one `NSLock`; mirrors `SignedEventsRegistry`. Drain-once retained, so a result frame arriving between `dispatchSilent` and `awaitResult` registration is **buffered**, then consumed (no lost result).
- Registration ordering is dispatch→await, but the buffer makes it race-free (no need to register before dispatch).
- Timeout task calls `cancel()` (removes+resumes the waiter), then the task group's `cancelAll()` kills the 3600s sleep. No continuation leak on either win path. Minor: if a result arrives in the same `ingest` after `cancel` removed the waiter, it gets buffered and never drained — bounded memory only, not a hang.

### 4. D13/D0 compliance — CLEAN ✅
No signing, no URLSession/HTTP in the Swift path. Swift writes a temp file, `dispatchSilent`es `nmp.blossom.upload`, awaits the projected result. Temp file cleaned via `defer { try? FileManager.default.removeItem(at: tmpURL) }`.

### 5. Call-site parity + hygiene — GOOD ✅
- Both sites preserve UX (loading/error state, resulting URL used identically).
- `snapshot.rs` injection is additive + D6-safe: `action_results` key added only when the sidecar decodes non-empty; absent/malformed → `None` → no key, no throw. Rust unit tests cover absent + malformed paths.
- **Golden test byte-identical: YES** — `snapshot_golden_tests.rs` is unchanged; steady-state frames carry no settled action → no `action_results` key → existing golden bytes unchanged.
- `register.rs` calls `nmp_blossom::register_actions(app_mut)`; signature `(&mut impl ActionRegistrar)` matches `NmpApp`. Correct.
- LOC ceilings respected (snapshot.rs 484<500; new Swift files 104/119).
- Audio-path deferral reasoning is **sound**: per-podcast NIP-F4 keys live in Podcast's `PodcastKeyStore`, not the NMP identity roster that `signer_pubkey` resolves against, so `blossom.rs` correctly stays on direct `Keys` signing. Well-documented in the BACKLOG diff.

### Test-coverage gap (follow-up, not blocking)
The new `snapshot_action_results_tests.rs` covers only D6 absent/malformed. The `empty_results_yields_none` test is a **no-op stub** (the author hit `encode_action_results` being `pub(crate)` in nmp-core and gave up). There is **no in-repo success-path test** proving Rust-encode → Swift-decode-shape reaches `url`. Upstream nmp-core/nmp-blossom tests cover their halves, but the seam contract this PR introduces is untested here. Recommend a follow-up fixture test (the FFI decode path `decode_action_results_sidecar` round-trip with a real BlobDescriptor result) — this is exactly the kind of bridge-decode contract that has silently broken before (per the FFI snake_case memory).

---
**Bottom line:** Architecturally sound, shape-correct, D13/D0-clean. One build-breaking orphan (`BlossomUploaderTests.swift`) must be deleted before merge. Fix is trivial; re-run `xcodebuild build-for-testing` (or the exhaustive grep) to confirm zero remaining references. After that, this is an APPROVE.
