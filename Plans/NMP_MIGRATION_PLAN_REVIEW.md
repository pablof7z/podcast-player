# NMP Migration Plan — Senior Review

**Reviewer:** claude-sonnet-4-6 (standing in for Opus 4.7)
**Plan author:** Opus 4.7
**Plan file:** `Plans/NMP_MIGRATION_PLAN.md`
**Date:** 2026-05-25

---

## Verdict: SHIP-WITH-REVISIONS

The plan's skeleton is sound. The milestone ordering is defensible, the capability-bridge pattern is architecturally correct, and the proposed crate layout follows NMP conventions closely enough to be workable. However, eight specific defects range from blocking (the plan's own Definition of Done cannot be met as written) to serious (an NMP doctrine violation endorsed in the text, unbuilt infrastructure presented as available, six files missing from the Nip46 inventory). None of these require discarding the plan. Each requires a concrete correction before any agent starts milestone work.

---

## Top 5 Strengths

**1. Capability bridge modeling is correct.**
The ten capability namespaces (audio, download, notifications, stt, tts, vector, spotlight, carplay, keyring, http) are identified at the right granularity, each maps to a typed `Request`/`Result` pair, and the pattern matches `nmp-core/src/substrate/capability.rs`'s `CapabilityModule` trait. This is the hardest architectural decision and the plan gets it right.

**2. Chirp mirror structure for the podcast app.**
The proposed `apps/podcast/nmp-app-podcast/` layout mirrors `apps/chirp/nmp-app-chirp/` almost exactly. The FFI entry point `nmp_app_podcast_register(app, viewer_pubkey) -> *mut PodcastHandle` is the correct signature (verified against `apps/chirp/nmp-app-chirp/src/ffi/register.rs`). The six podcast-specific Rust sub-crates are a reasonable decomposition.

**3. Milestone ordering respects real dependencies.**
M5 (audio engine) and M6 (feed sync) are correctly parallelized before M7 (playback UI wiring), which itself gates M9 (agent). The sequencing does not create phantom dependencies. M0/M1 (scaffold + entitlements) have no external blockers. This is executable as written.

**4. BYOK keychain strategy is the right approach.**
§10.2's decision to migrate keys via a one-time Keychain read rather than forcing re-pairing is the correct user-experience call. The access-group issue (see Issue #6 below) is a fixable implementation detail, not a strategy flaw.

**5. Planning discipline acknowledgment.**
§10.5 identifies 16 BACKLOG entries that must be filed in `docs/BACKLOG.md` before execution begins. The plan recognizes its own incompleteness here. That is honest and the right instinct, even though the entries have not yet been filed (see Issue #8 below).

---

## Top 10 Issues Ranked by Severity

### Issue 1 — BLOCKING: §6.12's "copy verbatim" disposition is false for ~15+ Features/ files

**Severity:** Blocking. The plan's Definition of Done states: "no native business logic." §6.12 marks the entire `Features/` directory as disposition "C" (copy verbatim). At least the following files contain business logic that must move to Rust and therefore cannot be copied verbatim:

| File | LOC | Business logic present |
|------|-----|------------------------|
| `Features/Player/PlaybackState.swift` | 497 | Sleep timer, end-of-episode detection, queue pop, persistence callbacks |
| `Features/Agent/AgentChatSession.swift` | ~400 | Turn loop, 3-hour auto-resume window, retry/regenerate |
| `Features/Agent/AgentOpenRouterClient.swift` | 271 | HTTP request construction, retry logic, streaming |
| `Features/Agent/AgentOllamaClient.swift` | ~200 | Local inference client |
| `Features/Agent/AgentLLMClient.swift` | ~100 | Routing policy between backends |
| `Features/Agent/AgentChatTitleGenerator.swift` | ~80 | Title heuristics |
| `Features/Briefings/BriefingsViewModel.swift` | ~300 | `BriefingComposer + BriefingStorage` |
| `Features/Search/PodcastSearchViewModel.swift` | ~200 | Owns `RAGService.shared` — not rendering |
| `Features/Settings/AI/OpenRouterModelCatalogService.swift` | 292 | Fetches and merges three catalogs (OpenRouter, models.dev, Ollama) |
| `Features/Feedback/FeedbackStore.swift` | 369 | `FeedbackRelayClient` — independent Nostr relay connection to `wss://relay.tenex.chat` |

Marking all of these "C" is not an oversight in one file. It is a systematic misclassification of the entire `Features/` directory. The FeedbackStore case is particularly serious: it maintains its own live Nostr relay connection that is completely absent from the plan's architecture — no destination crate, no capability namespace, no migration milestone.

**Fix:** Replace §6.12's blanket "C" with a per-file disposition table. For each file above, assign "D" (delete/rewrite in Rust) and name the destination Rust module. The FeedbackStore relay client must be routed through nmp-core's relay pool and dispatched as a `FeedbackAction`; it is not a simple copy.

---

### Issue 2 — BLOCKING: §11.1 depends on per-view emit rates that do not exist in nmp-core

**Severity:** Blocking. §11.1 states: "agentChat.streamingTurn delivered at ~30 Hz separately from the rest of the snapshot." This requires per-view emit rate configuration. Inspecting `nmp-core/src/actor/tick.rs` reveals a single global `emit_hz: 30` applied to all views simultaneously. There is no mechanism to configure different emit rates for different snapshot fields.

The `flush_due` function gates on a single wall-clock interval. There is no `StreamingView` variant, no `per_view_hz` table, no override API.

Building this feature is not trivial — it requires changes to `nmp-core`'s tick loop, possibly a new snapshot field category, and new FFI surface. This is M2-equivalent infra work, not a configuration knob.

**Fix:** Either (a) remove the per-view streaming claim and accept 30 Hz as the floor for all snapshot fields including streaming tokens, or (b) add a prerequisite milestone "M-pre: add per-view emit-rate override to nmp-core" with an NMP-repo PR before M7. Do not leave §11.1 as written — it describes infrastructure that does not exist and will not exist unless someone builds it.

---

### Issue 3 — BLOCKING: §11.4 endorses polling — violates NMP doctrine

**Severity:** Blocking. NMP `AGENTS.md` states: "No polling — ever. Polling is forbidden at every layer of the stack. This means no sleep + check loops, no Timer.scheduledTimer querying state, no try_recv + sleep spin loops."

§11.4 explicitly proposes "Rust polling" for AssemblyAI transcription progress. This is not an edge case or ambiguous phrasing. The plan acknowledges it is polling and endorses it.

**Fix:** Replace the polling loop with AssemblyAI's webhook callback or SSE endpoint. The transcription capability's `Request` enum should include a `webhookUrl` field; the capability implementation registers a local HTTP endpoint (or uses a push notification token) and emits a `SpeechToTextResult` action when AssemblyAI calls back. If AssemblyAI's API does not support push in the required deployment context, the plan must document that constraint and propose an event-driven alternative (e.g., background URLSession completion handler). Under no circumstances is a sleep-loop acceptable.

---

### Issue 4 — Serious: nmp-threading exists and is ignored; plan invents redundant NIP-10 code

**Severity:** Serious. §5.9 (peer conversations) proposes that `podcast-agent::peer::relay_bridge` implement NIP-10 reply-chain reconstruction at approximately 300 LOC. The crate `nmp-threading` already exists in the NMP workspace and provides a kind-agnostic `Grouper` for reply chains.

This is a D4 violation (single writer per fact). Two independent NIP-10 groupers in the same logical system means thread ordering can diverge between Chirp and the podcast agent's peer conversation feature. It also means maintaining two implementations.

**Fix:** Remove `podcast-agent::peer::relay_bridge`'s NIP-10 grouper. Add `nmp-threading` as a dependency of `podcast-agent`. File a BACKLOG entry if `nmp-threading`'s API needs extension to handle the podcast peer use case.

---

### Issue 5 — Serious: Six Nip46 service files are missing from the migration inventory

**Severity:** Serious. §6.9 lists three Nip46 files for migration: `NostrSigner.swift`, `RemoteSigner.swift`, `RemoteSigner+NostrConnect.swift`. Inspecting `App/Sources/Services/Nip46/` reveals nine files:

```
BunkerURI.swift
ChaCha20.swift
Nip44.swift
Nip46Message.swift
NostrSigner.swift                     (plan covers this)
RemoteSigner+NostrConnect.swift       (plan covers this)
RemoteSigner.swift                    (plan covers this)
RemoteSignerClient.swift
RemoteSignerTransport.swift
```

The six missing files are not rendering code. `ChaCha20.swift` and `Nip44.swift` are cryptographic implementations; `BunkerURI.swift` is a URI parser; `Nip46Message.swift` is a protocol message type; `RemoteSignerClient.swift` and `RemoteSignerTransport.swift` are network and messaging logic. All six must move to Rust (the crypto to `nmp-nip44`, the rest to the proposed `nmp-nip46` crate or `podcast-core`).

**Fix:** Extend §6.9's inventory. For each missing file, assign a Rust destination and a milestone. `ChaCha20.swift` and `Nip44.swift` may already be covered by `nmp-nip44` (verify); if so, the plan must say so explicitly rather than omitting them.

---

### Issue 6 — Serious: §10.2 BYOK migration claim is unsupported — entitlements do not match

**Severity:** Serious. §10.2 states: "Keys can be migrated from the existing Keychain items into NMP's keyring capability with no user re-pairing required." This claim rests on being able to read the existing app's Keychain items from the new NMP-hosted app binary.

Inspecting the entitlements files reveals a mismatch:
- `ios/Chirp/Chirp/Chirp.entitlements` has `keychain-access-groups: ["$(AppIdentifierPrefix)$(CFBundleIdentifier)"]`
- `App/Resources/Podcastr.entitlements` has `com.apple.security.application-groups` and `com.apple.developer.ubiquity-kvstore-identifier` but **no `keychain-access-groups` key**

Without a matching `keychain-access-groups` entitlement, a new binary cannot read Keychain items created by a different bundle ID. Whether items are accessible depends on the `kSecAttrAccessGroup` that was used when they were written. If the existing app wrote keys without an explicit access group (using the default per-app group), the new NMP binary — running under a different bundle ID — cannot read them.

**Fix:** Before claiming no re-pairing is required, (a) audit which `kSecAttrAccessGroup` the existing podcast app uses when writing nsec/bunker credentials, (b) determine whether the new app's bundle ID will differ, and (c) if the IDs differ, either add a shared `keychain-access-groups` entitlement to both the old and new apps (requires a transitional build shipped to existing users before the new app replaces the old one), or accept that re-pairing is required and document the UX migration flow. This must not be hand-waved.

---

### Issue 7 — Serious: Plan contains three factual errors that will mislead agents

**Severity:** Serious (not blocking, but will cause wasted work).

**7a. RootView.swift LOC.** §6.1 states: "RootView.swift: 822 LOC." Actual count: 416 LOC. The 822 figure appears to be a sum across multiple App/ files. Agents relying on this to scope work will misallocate time.

**7b. NIP-19 already fully implemented.** §3.1 describes `nmp-nip19` as "proposed-new, may exist in part." Inspecting `nmp-core/src/nip19.rs` reveals a complete implementation: `npub`, `nsec`, `note`, `nprofile`, `nevent`, `naddr` — all present. The plan should mark this "existing, no new crate needed" and remove it from the new-crate creation list.

**7c. `podcast-agent` crate size.** §8 presents a 30-module breakdown of `podcast-agent` and states it is within the 300/500 LOC file-size doctrine. No individual module is analyzed. Several modules (e.g., `turn_loop`, `peer::relay_bridge`, `rag::embed_worker`) are described in ways that strongly suggest they will exceed 300 LOC. The claim is unverifiable and likely wrong for at least 5-8 of the 30 modules. Agents must be warned to split on first approach rather than assume the estimates are accurate.

**Fix:** Correct §6.1's LOC. Update §3.1 to remove `nmp-nip19` from the new-crate list. Add a note to §8 warning that module size estimates are illustrative and the 300 LOC soft limit applies to each file individually.

---

### Issue 8 — Moderate: §10.5's 16 BACKLOG entries must be filed before M0 starts

**Severity:** Moderate. The plan correctly identifies that 16 BACKLOG entries need to be added to `docs/BACKLOG.md`. As of the date of this review, zero of these entries exist in the BACKLOG file. NMP planning discipline (`AGENTS.md §Planning discipline`) requires that pending work live in one of three canonical files — not in a migration plan document that is not one of those three.

Until these entries are filed, any agent starting M0 work is operating without a canonical record of the known violations and decisions. If any of those violations are encountered mid-sprint, the agent will not know they are already identified, and may create duplicate or conflicting entries.

**Fix:** File all 16 BACKLOG entries in `docs/BACKLOG.md` before any agent starts M0. This is a prerequisite to execution, not a nice-to-have.

---

### Issue 9 — Moderate: D11, D13, D15 are missing from the doctrine walkthrough

**Severity:** Moderate. The plan's §1.5 lists D0-D10 as the binding doctrines and conducts a compliance walkthrough against them. However, doctrine-lint contains rules for D11, D13, and D15:

- **D11:** One door per publish capability. The plan introduces multiple event-publishing paths (NIP-74 podcast events, NIP-10 peer replies, NIP-57 zaps, feedback relay) and never audits them against D11.
- **D13:** DM-path raw-key isolation. The peer conversation feature (`podcast-agent::peer`) exchanges NIP-17 DMs. The plan does not verify that the key used for NIP-17 encryption never crosses the FFI boundary in raw form.
- **D15:** Host-supplied closures must be wrapped in `catch_unwind`. Relevant for the audio capability bridge where Swift closures may be called from Rust threads.

**Fix:** Add D11, D13, D15 to §1.5 and perform the same per-doctrine walkthrough. The agent implementing M9 (peer conversations) needs D13 guidance before writing that code.

---

### Issue 10 — Moderate: `AppStateStore+AdSegments` has no Rust destination

**Severity:** Moderate. §6.2 states all 27 `State/` files are disposition "D" (delete). The deletion list for M2 covers the obvious ones but does not name `AppStateStore+AdSegments.swift`. Ad segment state (chapter-level skip markers, dynamic insertion points) is non-trivial domain logic. If this state is not explicitly mapped to a Rust module, it will either be silently dropped (breaking ad-skip UX) or re-invented in Swift (violating D0).

**Fix:** Name `AppStateStore+AdSegments` explicitly in the M2 deletion checklist and assign it a destination Rust module (likely `podcast-core::episode::segments` or similar). If ad segments are intentionally dropped from v1, document that decision in the BACKLOG as a known regression.

---

## Doctrine Walkthrough (D0-D10)

**D0 — No app nouns in nmp-core:** The six proposed podcast crates live under `apps/podcast/` or as new NMP crates named by NIP number — correct. No podcast types are proposed inside `nmp-core`. Pass.

**D1 — Best-effort rendering:** The `PodcastUpdate` snapshot design correctly allows partial fields. Swift render code must never block on absent fields. The plan says this but does not audit each snapshot field for optionality. Conditional pass — requires snapshot schema review at M3.

**D2 — Negentropy first:** §5.2 correctly routes feed sync through negentropy-based event reconciliation. Pass.

**D3 — Outbox routing automatic:** §5.6 states NIP-74 events are published via the user's NIP-65 outbox relay list (confirmed in the existing codebase). The plan does not propose any manual relay routing. Pass.

**D4 — Single writer per fact:** Issue #4 above is a D4 violation. The `nmp-threading` duplicate fails this doctrine. Conditional fail — fixable by removing the duplicate grouper.

**D5 — Snapshots bounded by what's open:** The plan does not bound `PodcastUpdate.episodeList` to the visible screen's page range. If the library has 2000+ episodes and all are serialized into every snapshot, this will OOM on constrained devices. The plan should specify pagination/windowing in the snapshot schema. Conditional pass with concern.

**D6 — Errors never cross FFI as exceptions:** §4.3's capability result types use `Result<T, CapabilityError>` serialized to JSON. Correct pattern. Pass.

**D7 — Capabilities report, never decide policy:** Issue #3's polling loop is a D7 violation — the capability implementation would be deciding retry policy. Beyond that, `OpenRouterModelCatalogService.swift` performs merge/selection logic that belongs in Rust. Fail on §11.4; conditional fail on §6.12's "C" disposition for `OpenRouterModelCatalogService`.

**D8 — ≤60 Hz per view:** §11.1's 30 Hz streaming token claim is described as a separate rate, implying it would need to be additive with the main 30 Hz tick. Two concurrent 30 Hz channels is within the 60 Hz budget in theory, but since the infrastructure does not exist (Issue #2), this cannot be verified. Pending.

**D9 — Kernel owns time:** The plan does not propose any Swift-side timers for business decisions. Sleep timer and briefing schedule are both routed through Rust. Pass.

**D10 — Provenance:** NIP-74 events reference episode GUIDs. The plan does not specify how provenance is preserved when a local RSS episode is promoted to a NIP-74 event — i.e., whether the original feed URL and GUID survive the round-trip. This needs a one-sentence spec in §5.6. Conditional pass.

---

## Missing Pieces

- `FeedbackStore`'s `FeedbackRelayClient` (live WebSocket to `wss://relay.tenex.chat`) has no destination crate, no capability mapping, and no milestone. This is a complete feature that vanishes in the plan.
- `AppStateStore+AdSegments` destination (see Issue #10).
- D11, D13, D15 doctrine walkthrough (see Issue #9).
- `BunkerURI.swift`, `ChaCha20.swift`, `Nip44.swift`, `Nip46Message.swift`, `RemoteSignerClient.swift`, `RemoteSignerTransport.swift` — all missing from the Nip46 inventory (see Issue #5).
- Per-view emit-rate NMP infrastructure — either commit to building it or remove the claim (see Issue #2).
- `PodcastUpdate` snapshot schema: field-level optionality spec, pagination/windowing strategy for episode list.
- `AgentChatSession`'s 3-hour auto-resume window — which Rust module owns this timer? It is business logic (D0) and must not stay in Swift.
- Vector index migration: §10.1 covers JSON UserDefaults → LMDB and wiki pages, but does not address the existing `sqlite-vec` index used by `RAGService`. What happens to the existing vectors? Are they re-indexed on first launch (expensive) or migrated (requires reading the old schema)?
- Audio cache migration: §10.1 does not address already-downloaded episode MP3 files. Are they re-downloaded on first launch (expensive on metered connections) or is the existing cache directory adopted by the new app? The download capability's `Result` enum must define whether it accepts a pre-existing file path or always writes a new one.
- Live Activity budget: the plan mentions CarPlay capability but does not address iOS Live Activity updates (playback controls in Dynamic Island / Lock Screen), which have a strict 1 Hz update cap and require ActivityKit, a separate capability namespace.
- Audio session interruption handling: phone calls, Siri, other audio apps. This is OS-level policy that must be modeled as a capability event, not handled in Swift.

---

## Per-Milestone Risk

**M0 — Scaffold:** Low risk. Standard crate + Xcode project wiring. No blockers.

**M1 — Entitlements + signing:** Medium risk. The keychain-access-groups issue (Issue #6) is discovered here. Do not proceed past M1 without resolving the BYOK entitlement audit.

**M2 — State deletion:** Medium risk. `AppStateStore+AdSegments` has no Rust destination; deletion will break ad-skip silently. Needs explicit mapping before this milestone starts.

**M3 — Snapshot schema + FFI:** Medium risk. D5 snapshot bounding must be addressed. The schema must specify pagination or the episode list will bloat every snapshot.

**M4 — Authentication / NIP-46:** High risk. Six Nip46 files are missing from the inventory (Issue #5). Do not start M4 without completing the inventory.

**M5 — Audio engine:** Medium-high risk. Audio session interruption (phone calls, Siri) is not modeled. Sleep timer is business logic currently in `PlaybackState.swift`; must be moved to Rust in this milestone, not deferred.

**M6 — Feed sync:** Low-medium risk. The plan covers this well. Main risk is negentropy relay availability in the test environment.

**M7 — Playback UI wiring:** High risk. Blocked on two things: (a) `PlaybackState.swift`'s business logic must be fully migrated to Rust (not just "wired"), and (b) the per-view emit-rate infrastructure (Issue #2) must be resolved before streaming token UI is attempted here.

**M8 — Transcription / STT:** High risk. AssemblyAI polling is a doctrine violation (Issue #3). Must be replaced with webhook/callback before this milestone is designed further.

**M9 — Agent / peer conversations:** High risk. Depends on M7 (full playback) and M8 (transcription). NIP-10 grouper duplication (Issue #4) and D13 raw-key isolation for NIP-17 must both be addressed.

**M10 — Knowledge / RAG:** Medium risk. Vector index migration from `sqlite-vec` is unspecified. Re-indexing on first launch at scale (thousands of episodes) may cause a multi-minute freeze.

**M11 — Briefings:** Low-medium risk. `BriefingsViewModel`'s `BriefingComposer + BriefingStorage` must move to Rust; the plan marks it "C."

**M12 — Discovery / NIP-74:** Low risk. This is already partially implemented in the existing app. Main risk is relay compatibility testing.

**M13 — Polish / release:** Medium risk. This milestone is where Live Activity, CarPlay, and Spotlight indexing land. CarPlay is acknowledged; Live Activity is not modeled at all.

---

## Effort Estimate Critique

The plan estimates 8-12 person-months. This range is plausible for the described scope under two conditions that the plan does not verify:

1. **The "copy verbatim" Features/ files are not actually copied.** If ~15 files containing business logic must instead be ported to Rust (Issue #1), the effort for M5, M7, M9, and M11 each grows by roughly 2-3 weeks. That is 8-12 weeks of additional work not in the estimate — potentially 2-3 months.

2. **The NMP infrastructure gaps are handled.** Building per-view emit rates (Issue #2) or switching AssemblyAI from polling to webhook (Issue #3) are not in the plan's scope and not in the estimate. These are 1-3 week items each.

Revised honest range: **10-16 person-months** if Issues 1-3 are addressed properly. If they are papered over with hacks, the estimate will be met but the codebase will fail the NMP doctrine review at merge time and the milestones will be reopened.

The plan does not account for:
- The FeedbackStore relay client rewrite (unplanned feature, ~2-3 weeks)
- Vector index migration complexity (~1 week)
- Live Activity capability namespace (~1 week)
- Entitlement transition build for BYOK keychain migration (~1 week if bundle IDs differ)

---

## Recommended Changes Before Adopting the Plan

1. **Replace §6.12's blanket "C" for Features/ with a per-file disposition table.** This is the highest-leverage fix: it eliminates the false promise that the migration is mostly copy-paste, and forces explicit Rust module assignments for the 15+ files containing business logic.

2. **File all 16 BACKLOG entries in `docs/BACKLOG.md` immediately.** Do not start M0 without a canonical record of known violations.

3. **Resolve the per-view emit-rate question in §11.1 before M7.** Either commit to building it in NMP (open an NMP-repo issue, add to NMP BACKLOG) or remove the streaming-token-at-30-Hz claim and accept that streaming tokens are delivered at the global tick rate.

4. **Replace §11.4's polling design with an event-driven AssemblyAI integration.** Propose either webhook + local callback HTTP server, or background URLSession with a completion notification that dispatches a `TranscriptionComplete` action.

5. **Complete the Nip46 inventory (Issue #5) and audit `App/Sources/Services/Nip46/` file by file.** Add the six missing files with Rust destinations.

6. **Add FeedbackStore to the migration plan.** Assign `FeedbackRelayClient` to a destination crate (likely `podcast-core::feedback` or a thin addition to the existing Nostr relay pool), name a milestone (M6 or M12), and ensure the `wss://relay.tenex.chat` connection is routed through nmp-core.

7. **Add D11, D13, D15 to the doctrine walkthrough** with specific guidance for the peer-conversation (D13) and multi-publisher (D11) features.

8. **Correct the three factual errors:** RootView.swift is 416 LOC (not 822), NIP-19 is fully implemented (no new crate needed), and `podcast-agent` module size estimates are illustrative only.

---

## Risk Gaps Not Covered in the Plan

The following risk categories are absent from the plan's risk section. Each represents a real failure mode that agents should be aware of before starting the relevant milestone.

**10+ hour episodes.** The existing app supports multi-hour lecture recordings and conference talks. AVPlayer can seek within a locally cached file efficiently, but if the file is not fully downloaded, seeking into an un-buffered region causes a stall. The plan does not specify how the download capability handles partial-file seeking, whether the audio capability reports buffer progress to Rust, or how the snapshot expresses "chapter N seekable, chapter N+1 pending." This is a UX regression risk for the podcast app's long-content audience.

**Poor network / download resumability.** Background downloads via `URLSession` support byte-range resumption only if the server returns `Accept-Ranges: bytes` and the client preserves the resume data. The plan specifies a `DownloadCapability` but does not specify how resume tokens are stored (in Rust state? in a Keychain item? in a temp file?). If the device loses power mid-download and the resume token is lost, the download restarts from byte 0. This must be specified explicitly in the download capability's `Result` enum.

**OpenRouter and Ollama OAuth / API key management.** `OpenRouterModelCatalogService.swift` (292 LOC) fetches and merges three external catalogs and holds an OAuth token. The plan marks this "C" (copy verbatim) — a D0 violation. The OAuth token refresh loop is business logic. The destination Rust module must handle token expiry, the refresh flow, and the three-catalog merge. This is non-trivial and is currently entirely missing from the plan's Rust module inventory.

**Agent runaway (cost and loop bounds).** The `turn_loop` in `podcast-agent` can call an LLM repeatedly. There is no cap in the plan on maximum turns per session, no cost budget guard, and no mention of what happens when an LLM returns a tool call that causes another tool call in a cycle. This is a real risk for users on metered API plans. The `turn_loop` Rust module must define a `max_turns: u32` cap and a `token_budget: u64` ceiling, both configurable via the snapshot and settable from the Settings UI.

**iOS 26 sqlite-vec quirks.** `sqlite-vec` on iOS runs in-process as a SQLite extension. iOS 26 (if that is the target deployment) may introduce changes to SQLite's bundled version or extension loading restrictions under the new privacy manifest requirements. The plan references sqlite-vec for the RAG vector store without noting that extension availability must be verified at runtime and a graceful degradation path (disable vector search, fall back to full-text) must exist.

**"Near-trivial new platform" claim.** The plan states — and the user's primary success criterion confirms — that adding Android, web, or desktop should become near-trivial after migration. This claim deserves direct examination rather than acceptance.

What an Android engineer would actually have to write from scratch:
- A Kotlin/JNI binding layer analogous to `KernelBridge.swift` (~1500-2000 LOC Kotlin)
- A Compose render layer that reads `PodcastUpdate` snapshots and builds the full UI (~30+ screens)
- Implementations of all ten capability namespaces in Kotlin: `ExoPlayer` for audio, `WorkManager` for background downloads, `SpeechRecognizer`/AssemblyAI for STT, `MediaSession` for CarPlay equivalent (Android Auto), vector store (sqlite-vec on Android), Spotlight equivalent (Android AppSearch), notification channels, TTS
- A full NIP-46 integration in Kotlin mirroring the Swift remote signer
- Android-specific entitlements, background modes, and battery optimization exemptions

This is 3-5 months of Kotlin engineering, not "trivial." The correct characterization is: the business logic is shared and does not need to be re-implemented; only the rendering and capability execution layers need to be written. That is a significant saving, but it is not trivial. The plan's language should be corrected to set accurate expectations.

---

## Open Questions for the Plan Author

1. **FeedbackStore relay client:** Where does `FeedbackRelayClient` (connecting to `wss://relay.tenex.chat`) land in the architecture? Is this a first-class NMP relay pool connection or a separate feedback capability? Who owns the relay URL configuration?

2. **Ad segments:** Is `AppStateStore+AdSegments` intentionally dropped from v1, or is it an oversight? If dropped, what is the regression plan for users who rely on ad-skip?

3. **Vector index migration:** Does the existing `sqlite-vec` index get re-indexed at first launch (accepting a cold start delay), or is there a migration path from the old schema? What is the acceptable cold-start budget?

4. **Live Activity:** Is iOS Live Activity (Dynamic Island playback controls) in scope for v1? If yes, which milestone? The plan covers CarPlay but not Live Activity, and they share some of the same media metadata concerns.

5. **Bundle ID continuity:** Will the NMP-hosted podcast app ship under the same bundle ID as the existing app (enabling a seamless App Store update) or a new one? This determines whether the BYOK keychain migration is trivial or requires a transitional build.

6. **AssemblyAI fallback:** If the webhook/callback approach for transcription is not feasible in the deployment environment, what is the fallback? On-device Whisper only? The plan presents AssemblyAI as the primary path; the fallback is not specified.

7. **`BriefingComposer` + `BriefingStorage`:** The plan marks `BriefingsViewModel.swift` as "C." Does the author intend `BriefingComposer` and `BriefingStorage` to remain in Swift? If so, what doctrine permits this? If not, which Rust module owns briefing composition and where does it land in the milestone plan?

8. **`AgentChatSession`'s 3-hour auto-resume window:** This is an explicit business rule (if the user returns within 3 hours, resume the prior turn context). Which Rust module owns this timer and state? The plan marks `AgentChatSession.swift` as "C," which would leave this rule in Swift — a D0 violation.

---
