# Pod0 Validation Command Center

## Purpose

This plan tracks the public validation hub requested for Pod0. The hub is the
place where agents publish scenario coverage, screenshots, per-screenshot UX
critique, performance evidence, LLM cassette coverage, NMP/chirp sync findings,
GitHub issues, fix PRs, and revalidation results.

Live report:
<https://pablof7z.github.io/podcast-player/>

## Current State

- GitHub Pages is enabled from the `gh-pages` branch and serves the live report.
- Initial report content was verified publicly on 2026-07-05 with HTTP 200 for
  the page, stylesheet, and representative screenshot assets.
- The report currently publishes the existing 73 simulator runbooks, existing
  screenshot inventory, evidence contract, performance budget placeholders, NMP
  pin status, and the active issue queue.
- PR #705 adds a 264-scenario BDD catalog under `docs/testing/scenarios/catalog/`.
  That catalog is planning-level scenario coverage; it does not yet create
  runnable automation, cassettes, or metric ingestion.
- Full product validation is not complete. The report must stay explicit about
  missing evidence instead of marking unrun scenarios green.

## Tracking Issues

- #700 - Expand Pod0 BDD catalog to hundreds of executable scenarios.
- #701 - Add cassette record/replay for LLM and STT scenario validation.
- #702 - Publish per-scenario performance metrics in the Pod0 validation report.
- #703 - Populate gh-pages report with screenshot-level UX critique.
- #704 - Audit Pod0 against latest NMP and chirp-shipped fixes.

## Report Evidence Contract

Every scenario row in the public report must eventually include:

- Given/When/Then scenario text and deterministic fixture/precondition state.
- Screenshot evidence for every meaningful step.
- Screenshot-level UX critique covering layout, hierarchy, accessibility,
  animation, error states, and liquid glass integration.
- Performance metrics and budget disposition for the scenario.
- Cassette/replay IDs for LLM, STT, TTS, search, relay, and provider-backed
  dependencies.
- NMP/RMP boundary markers, especially D0-D10 ownership and bounded-reactivity
  rules.
- Linked GitHub issue for every imperfection, linked fix PR, and revalidation
  evidence after the fix lands.

## Publication Rules

- `gh-pages` is the public deployment branch.
- Main-branch planning and test artifacts remain in canonical docs locations:
  `docs/plan.md`, `docs/BACKLOG.md`, and `docs/testing/scenarios/`.
- Do not claim a scenario passed until the report has current evidence for that
  exact build and scenario.
- When a report update references a new defect, file or link the GitHub issue in
  the same update.
- Keep the report factual when infrastructure is missing: "pending cassette
  harness" is better than an unverified pass.

## Next Work

1. Land PR #705 after its PR-description and diff-hygiene checks are fixed.
2. Implement the cassette record/replay harness for provider-backed scenarios.
3. Define the metric ingestion shape for scenario runs and publish it on
   `gh-pages`.
4. Run the first simulator scenario batch and publish screenshot-level critique.
5. Audit current NMP master and `../chirp` for applicable Pod0 fixes, then file
   specific child issues for every discovered gap.
