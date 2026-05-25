# Rules — non-negotiable

Read this first. Every PR is reviewed against this page. A change that
makes any of these rules harder to enforce is rewritten or rejected.

## 1. NMP doctrines D0–D10 bind every decision

Source: `/home/pablo/Work/nostrmultiplatform/docs/product-spec/overview-and-dx.md` §1.5.

- **D0** No app nouns in `nmp-core`. Podcast/Episode/Feed/Chapter belong
  in `apps/podcast/...`, never in `nmp-core`.
- **D1** Best-effort rendering — render now, refine in place. Placeholders
  are part of the type contract.
- **D2** Negentropy first, REQ second.
- **D3** Outbox routing automatic; manual relay selection is the opt-out.
- **D4** Single writer per fact; caches derive. No parallel caches.
- **D5** Snapshots bounded by what's open. Closed views contribute zero
  payload.
- **D6** Errors never cross FFI as exceptions. Surface as
  `toast: Option<String>` state fields.
- **D7** Capabilities report, never decide policy. Native bridges execute
  OS APIs; Rust decides retry/recovery/routing.
- **D8** Reactivity contract: composite reverse index · ≤60 Hz/view ·
  working-set bounded · zero per-event allocations after warmup.
- **D9** Kernel owns time. Signing, replaceable resolution, expirations,
  schedules — all Rust-side.
- **D10** Provenance preserved. Private events (gift-wrap, DMs) never
  escape to public relays.

Sonnet's review also called out D11 (one door per publish capability),
D13 (DM-path raw-key isolation), D15 (host-supplied closures wrapped in
`catch_unwind`). Treat them as binding even if they aren't in §1.5 yet.

## 2. No business logic in Swift

> "If you would write an `if` statement in Swift that decides what the
> app should do (not how it should look), that logic belongs in Rust.
> Native is rendering plus capability execution. Nothing else."

(From NMP's `AGENTS.md`.)

In practice this means:
- Swift code under `ios/Podcast/Podcast/Features/` is only `View` /
  `ViewModifier` / `ButtonStyle` / `Shape` / `EnvironmentKey` /
  `PreferenceKey` declarations and the thin presenter glue that calls
  `model.dispatch(...)` and reads `model.snapshot`.
- Swift code under `ios/Podcast/Podcast/Capabilities/` executes OS APIs
  in response to a typed request and reports raw results. It never
  decides retry, fallback, cache, batch, dedupe, throttle, or eligibility.
- Everywhere else: no business logic, period.

The lint gate `ci/no-business-logic-in-swift.sh` enforces:
- No `URLSession`, `URLRequest`, `WebSocket`, `Keychain*` API calls
  outside `Capabilities/`.
- No `class .*: ObservableObject`, `@Observable class`,
  `class .*Service`, `class .*Store`, `class .*Session`,
  `class .*Client`, `class .*Controller`, `class .*Composer`,
  `class .*ViewModel` under `Features/`.
- No imports of the removed legacy singletons (`AppStateStore`,
  `NostrRelayService`, `UserIdentityStore`, `RAGService`, `AgentSession`,
  `AudioEngine`, etc.).

## 3. Anti-hallucination: literal copy, not reimplementation

**Agents must not retype, rewrite, paraphrase, or "reimplement" any
SwiftUI view from notes or from inspection.** Hallucinated UI rewrites
are the single biggest historical failure mode of this kind of migration
and have produced a divergent UI in past attempts. Forbidden.

The procedure for any file under `App/Sources/Features/`:

1. `cp App/Sources/Features/<rel-path>.swift ios/Podcast/Podcast/Features/<rel-path>.swift`.
   This is the only acceptable way to move the file. Bytes preserved.
2. If the file is on the §6.12.1 split list (see
   [`05-migration-map.md`](05-migration-map.md)), the agent uses `Edit`
   with exact `old_string` / `new_string` to **excise** the
   business-logic class declaration. The View struct that remains is
   not touched at byte level.
3. A deterministic SwiftSyntax-based tool
   (`ci/migration/apply-token-swap.swift`) applies the token-swap table
   (see `05-migration-map.md` §C). It edits AST nodes, not raw strings,
   so SwiftUI modifier chains can't be mangled.
4. `git diff <legacy> <copied>` must consist only of approved patterns.
   `ci/ui-copy-fidelity.sh` enforces this.
5. Golden screenshots captured from the legacy app at migration start
   (under `ci/migration/golden-screenshots/legacy/`) are diffed against
   the migrated render. SwiftUI tolerance band applies.

If an agent ever has to type `struct SomeView: View {`, it is doing the
wrong thing. `cp` the file containing that struct instead.

The lint in §1.3 of the index forbids `Write`ing files under
`ios/Podcast/Podcast/Features/`. Agents may only invoke the migration
tooling via `Bash`, or `Edit` an already-copied file with the specific
approved patterns.

## 4. No polling

NMP's `AGENTS.md` is explicit: "No polling — ever. Polling is forbidden
at every layer of the stack."

This bans:
- `sleep` + check loops.
- `Timer.scheduledTimer` querying state.
- `try_recv` + `sleep` spin loops.
- `Task { while !cancelled { sleep; checkState() } }`.

Use blocking primitives or event-driven patterns instead:
- Rust channels: `recv()` / `recv_timeout()`. `try_recv()` only to drain
  on an existing tick.
- iOS: `AVFoundation` / `NWPathMonitor` / `NotificationCenter` callbacks;
  `URLSession` delegate methods; background-task completion handlers.

External APIs that don't push (e.g. AssemblyAI batch transcription): use
the API's webhook callback, or a background `URLSession` with completion
handler. Never a sleep loop.

## 5. File-size limits

- 300 LOC soft limit per hand-authored file.
- 500 LOC hard limit. The build fails for any new file over this.
- Generated, vendored, lockfile, binary, and benchmark artifacts are
  exempt.
- Split by cohesive ownership, not by technical role. See NMP's
  `AGENTS.md` "TEA organization" section.

Files in the legacy podcast tree exceeding the limit are split at copy
time (not in place — never edit the legacy source).

Note: Chirp's `KernelBridge.swift` is 1895 LOC and exceeds the limit.
It is grandfathered NMP debt. The Podcast bridge ships split from M0
into multiple `<300 LOC files.

## 6. Zero tolerance on hacks

- No "for now" workarounds.
- No `// TODO: fix this properly`.
- No fragmentation: every concept has exactly one canonical
  representation.
- Every change must seek the long-term-correct architecture, not the
  shortest path to green CI.
- "It works" is not acceptance; "It works and is architecturally
  correct" is.

A staged fix is allowed only when documented in NMP's `docs/BACKLOG.md`
with stages + deadlines. Undocumented temporary measures are forbidden.

## 7. Planning discipline

NMP has three canonical planning files: `docs/plan.md`,
`docs/BACKLOG.md`, `WIP.md`. The Podcastr repo has this `Plans/` tree
+ its own `Plans/WIP.md` (to be added).

- Every NMP-side work item that this migration creates is filed as a
  `BACKLOG.md` entry in NMP. Don't create new top-level planning files
  in NMP.
- Every Podcastr-side in-flight branch is recorded in
  `Plans/WIP.md` (to be added if not already present).
- This `Plans/nmp-migration/` directory is the authoritative migration
  plan. If a fact about the migration is wrong, edit the relevant page
  here — don't fork it elsewhere.
- The plan is updated in place when milestones complete (see each
  milestone page's exit checklist).

## 8. Commit hygiene

Per `/home/pablo/.claude/CLAUDE.md` and the Podcast `AGENTS.md`:
- No co-author lines.
- No "Claude" / "Codex" mentions in commit messages.
- No emojis.
- Use Conventional-Commits style prefixes (`feat:`, `fix:`,
  `refactor:`, `chore:`, `test:`, `docs:`) consistent with current
  Podcastr history (`git log` shows this pattern).
- Add a `whats-new.json` entry for any user-facing change per Podcastr
  `AGENTS.md`. Internal/refactoring commits skip this.

## 9. Worktree workflow

Per NMP's `AGENTS.md`:
- All implementation work happens in a git worktree owned by the agent.
- Don't edit from the shared root checkout for feature/fix/refactor work.
- Before starting: read `WIP.md` from the project base.
- On start: add a `WIP.md` entry (timestamp + one-line description +
  worktree path).
- On finish: open a PR (not draft) with TLDR, detailed overview,
  subjective decisions/tradeoffs. Remove the `WIP.md` entry.

## 10. Reviews before merge

Every NMP-side PR triggers `codex exec` post-merge review per NMP's
existing convention. Saved to `docs/perf/codex-reviews/<sha>.md`. Any
real concerns become NMP backlog entries.

Every podcast-app-side PR is reviewed by the orchestrator (the agent
running the merge gate). At minimum:
- Doctrine compliance (D0–D10).
- File-size limits.
- Anti-hallucination check (UI copy-fidelity if `Features/` touched).
- Test coverage at the scope of the change.
