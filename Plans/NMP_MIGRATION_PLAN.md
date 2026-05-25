# Podcastr → NMP Migration Plan — Index

**Status:** Draft (revision after Sonnet + Codex review)
**Last revised:** 2026-05-25

The migration moves the iOS podcast app at `/home/pablo/Work/podcast`
(583 Swift files, ~95K LOC) onto the Nostr Multi-Platform (NMP) framework
at `/home/pablo/Work/nostrmultiplatform`. The SwiftUI rendering is
literally copied (no agent retyping); all business logic moves to Rust.

This plan is split into many short files so multiple agents can pick up
work in parallel without stepping on each other. Each milestone file
lists self-contained work units. The shared reference pages stabilize the
contracts the milestones depend on.

---

## Read this first

1. [`nmp-migration/00-rules.md`](nmp-migration/00-rules.md) — the
   non-negotiable rules: doctrines, file-size limits, anti-hallucination,
   no-polling, no-business-logic-in-Swift.
2. [`nmp-migration/01-architecture.md`](nmp-migration/01-architecture.md)
   — target architecture, ownership table, dispatch/reconcile cycle.

## Reference pages (stable across milestones)

3. [`nmp-migration/02-crates.md`](nmp-migration/02-crates.md) — new NMP
   crates (Nostr-generic) and new `apps/podcast/` Rust crates
   (podcast-specific).
4. [`nmp-migration/03-capabilities.md`](nmp-migration/03-capabilities.md)
   — capability bridge contracts (audio, download, http, keychain, stt,
   tts, vector, notifications, spotlight, carplay).
5. [`nmp-migration/04-snapshot.md`](nmp-migration/04-snapshot.md) — the
   `PodcastUpdate` snapshot schema (Swift Decodable layout + per-field
   mapping to legacy `AppState`).
6. [`nmp-migration/05-migration-map.md`](nmp-migration/05-migration-map.md)
   — file-by-file disposition map for `App/Sources/**`. Split into
   sub-pages for size.
7. [`nmp-migration/06-cross-cutting.md`](nmp-migration/06-cross-cutting.md)
   — persistence migration, BYOK Keychain rebinding, NMP BACKLOG entries
   to file, test strategy, CI gates.
8. [`nmp-migration/07-risks.md`](nmp-migration/07-risks.md) — open
   questions and known failure modes.
9. [`nmp-migration/08-references.md`](nmp-migration/08-references.md) —
   files in NMP to study and copy.

## Milestones (sequenced; each ≤500 LOC, self-contained)

| ID | Title | Scale | Depends on | Blocks |
|---|---|---|---|---|
| [M0](nmp-migration/milestones/M00-bootstrap.md) | Bootstrap | S | none | M1–M13 |
| [M1](nmp-migration/milestones/M01-identity-nostr.md) | Identity & Nostr foundation | M | M0 | M2, M7, M10 |
| [M2](nmp-migration/milestones/M02-podcast-domain.md) | Podcast domain (feeds) | L | M1 | M3–M13 |
| [M3](nmp-migration/milestones/M03-audio-capability.md) | Audio capability | M | M2 | M4, M7, M9, M11 |
| [M4](nmp-migration/milestones/M04-download-capability.md) | Background download | M | M2 | M5, M11 |
| [M5](nmp-migration/milestones/M05-transcripts.md) | Transcripts | L | M4 | M6, M7, M8 |
| [M6](nmp-migration/milestones/M06-knowledge-rag.md) | Knowledge / RAG | L | M5 | M7, M9 |
| [M7](nmp-migration/milestones/M07-agent.md) | Agent | XL | M3, M6 | M8, M9, M10 |
| [M8](nmp-migration/milestones/M08-voice.md) | Voice (STT + TTS + barge-in) | M | M5, M7 | M9 |
| [M9](nmp-migration/milestones/M09-briefings.md) | Briefings | M | M3, M7, M8 | M11 |
| [M10](nmp-migration/milestones/M10-peer-nostr-blossom.md) | Peer agents + NIP-74 + Blossom | L | M1, M7 | M11 |
| [M11](nmp-migration/milestones/M11-platform-integrations.md) | CarPlay, Widgets, AppIntents, Spotlight, Handoff | M | M3, M4, M9, M10 | M12 |
| [M12](nmp-migration/milestones/M12-deletion-sweep.md) | Deletion sweep + lint gate | S | M0–M11 | M13 |
| [M13](nmp-migration/milestones/M13-second-platform.md) | Second-platform proof | L | M12 | — |

**Cross-platform proof is also required at M2 and M3** (per Codex review).
See those milestone pages for the Android/web stub deliverables.

---

## How to pick up work

1. Read `00-rules.md` and `01-architecture.md`. These are short and bind
   every PR.
2. Pick a milestone whose `Depends on` row is green. Open its page.
3. Scan the parallel work units. Each lists owner-blank slots; claim one
   by adding a `WIP.md` entry per NMP's agent workflow rule (and the
   Podcastr-repo equivalent).
4. Use isolated worktrees. Never edit the shared root.
5. When your work unit is done, run the unit's quality gates locally.
   If green, open a PR. PR body cites the milestone page + unit letter
   (e.g. "M2.C: podcast-feeds RSS parser").
6. The milestone is complete when every unit is merged + the milestone's
   integration checklist passes + Swift deletions named in the milestone
   are committed.
7. Remove your `WIP.md` entry. Update the milestone page's "Exit
   checklist" boxes.

---

## Process rule: do not redesign

The user has explicitly forbidden UI redesign. Every SwiftUI view under
`App/Sources/Features/**` is copied bit-for-bit via tooling described in
`nmp-migration/00-rules.md` §3 (anti-hallucination). Agents must not
`Write` files under `ios/Podcast/Podcast/Features/`. They invoke the
migration tooling and may `Edit` already-copied files only with the
approved exact-string patterns. Goldens enforce parity.

If you find yourself wanting to "improve" a view while migrating, stop
and file a separate post-migration ticket. The migration's only job is
to move the source of truth into Rust, not to change the product.

---

## Status snapshot

| Section | Status |
|---|---|
| Index (this file) | active |
| Shared rules + architecture | drafted; agents may begin reading |
| Crates / capabilities / snapshot reference | drafted |
| Migration map | drafted |
| Cross-cutting + risks + references | drafted |
| M0 Bootstrap | unclaimed |
| M1–M13 | unclaimed (blocked on predecessor) |

When a milestone is in progress, its line above gets the agent owner.
When it's done, its `Status` field on the milestone page itself shifts
to `complete` and the row above gets struck through.

---

## Archive

The earlier monolithic version of this plan lived at
`Plans/NMP_MIGRATION_PLAN.md` as a single 2488-line file. The two
independent reviews of it remain on disk for reference:

- [`NMP_MIGRATION_PLAN_REVIEW.md`](NMP_MIGRATION_PLAN_REVIEW.md) — Sonnet
  reviewer, found 8 ranked issues (3 blocking, 5 serious).
- [`NMP_MIGRATION_PLAN_CODEX_REVIEW.md`](NMP_MIGRATION_PLAN_CODEX_REVIEW.md)
  — codex exec, independent model. Found a foundation mismatch with the
  shipped NMP substrate plus 9 other ranked issues.

The split files below incorporate the agreed-on fixes from both
reviews. Each file calls out which review items it addresses.
