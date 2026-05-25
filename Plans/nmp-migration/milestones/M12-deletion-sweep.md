# M12 — Deletion sweep + lint gate

**Status:** unclaimed
**Scale:** S
**Depends on:** M0–M11
**Blocks:** M13
**Parallel work units:** 3

---

## Scope

Remove the legacy `App/Sources/` tree from the project. Make
`ios/Podcast/Podcast/` the sole Swift source. Tighten CI gates so any
reintroduction of business logic in Swift fails.

This milestone is straightforward but high-impact. The legacy tree
has been the source-of-truth reference for `ui-copy-fidelity.sh`
throughout the migration; once it's deleted, fidelity gates pin to
the goldens captured at migration start.

---

## Pre-flight

- [ ] M0–M11 exit checklists all green.
- [ ] `ci/migration/manifest.tsv` covers every file currently under
      `App/Sources/`.
- [ ] Every file in `App/Sources/` either:
      - has a migrated copy under `ios/Podcast/Podcast/`, OR
      - is named in some milestone's deletion list, OR
      - is a Resource (Assets, entitlements, whats-new.json) — copied
        not deleted.

Run the audit:

```sh
ci/migration/audit-coverage.sh
```

This script lists any file in `App/Sources/` not covered. The list
must be empty.

---

## Parallel work units

### Unit M12.A — Audit + final coverage

**Tasks:**
- [ ] Run `ci/migration/audit-coverage.sh`. Fix any uncovered files
      (add to manifest, port, or document as intentionally dropped).
- [ ] Ensure all Resource files are present in `ios/Podcast/Podcast/
      Resources/`.
- [ ] Update `Project.swift` / `Podcastr.xcodeproj` references so
      the new project replaces the legacy.

**Quality gates:**
- [ ] `audit-coverage.sh` empty.
- [ ] No legacy symbol references anywhere in the new tree.

### Unit M12.B — Delete legacy + tighten lints

**Tasks:**
- [ ] `git rm -r App/Sources/`.
- [ ] Update `ci/ui-copy-fidelity.sh` to validate against committed
      goldens only (since the legacy source is gone).
- [ ] Update `ci/no-business-logic-in-swift.sh` to scan only
      `ios/Podcast/Podcast/`.
- [ ] Add CI gate: `cargo build --workspace` from the NMP repo + iOS
      `xcodebuild Podcast` both must be green.
- [ ] Tighten Conventional Commits enforcement.

**Quality gates:**
- [ ] Whole repo builds.
- [ ] All scenario tests pass.
- [ ] All golden screenshots match.

### Unit M12.C — Documentation + Whats-new

**Tasks:**
- [ ] Update `README.md`: new architecture; new build instructions.
- [ ] Update `CLAUDE.md` if needed (point at this Plans/ tree).
- [ ] Final whats-new entry: "Podcastr is now built on NMP. Same app,
      smarter brains. Android / web / desktop coming."
- [ ] Update `Plans/NMP_MIGRATION_PLAN.md` (root index) status table:
      mark M0–M12 complete.
- [ ] Archive `Plans/NMP_MIGRATION_PLAN_REVIEW.md` and
      `Plans/NMP_MIGRATION_PLAN_CODEX_REVIEW.md` under
      `Plans/archive/` with reviewer credit preserved.

**Quality gates:**
- [ ] README accurately describes the new build.

---

## Sequential integration

- [ ] Merge M12.A.
- [ ] Merge M12.B.
- [ ] Merge M12.C.
- [ ] Ship a TestFlight build.
- [ ] Have ≥2 testers exercise every tab + every feature flow against
      the new build. Compare against legacy.

---

## Exit checklist

- [ ] `App/Sources/` deleted.
- [ ] `ios/Podcast/Podcast/` is the only Swift source.
- [ ] CI lint gates active and green.
- [ ] Golden screenshots match.
- [ ] All scenario tests pass.
- [ ] TestFlight build accepted.
- [ ] No regressions reported from manual smoke.
- [ ] M13 unblocked.

## Hand-off to M13

M13 stands up the second-platform full proof. M12 leaves the iOS app
clean enough that nothing in `ios/Podcast/Podcast/` looks like a
single-platform compromise.
