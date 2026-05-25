# M11 — Platform integrations

**Status:** unclaimed
**Scale:** M
**Depends on:** M3, M4, M9, M10
**Blocks:** M12
**Parallel work units:** 6

---

## Scope

CarPlay, Widgets, Live Activity, AppIntents, Spotlight, Handoff,
iCloud KV sync, Review prompt, Data export, Notifications. Each
becomes a thin capability executor driven by Rust-side decisions.

---

## Pre-flight

- [ ] M3, M4, M9, M10 exit green.
- [ ] BACKLOG entries for `cap-carplay`, `cap-spotlight`,
      `cap-handoff`, `cap-icloud`, `cap-review`, `cap-data-export`,
      `cap-notifications` all have ADRs landed.

---

## Parallel work units

### Unit M11.A — Notifications

**Tasks:**
- [ ] `Capabilities/NotificationsCapability.swift` (rewrite of
      legacy `NotificationService.swift` as executor).
- [ ] Cadence + budget decisions in `podcast-core::notifications`.
- [ ] Push token capture wired.

**Quality gates:**
- [ ] Permission flow works; scheduled notification fires.

### Unit M11.B — CarPlay

**Tasks:**
- [ ] `Capabilities/CarPlayCapability.swift` subscribes to
      `model.$snapshot` via Combine; rebuilds templates on
      `car_play.rev` advance.
- [ ] Browse-tree + queue policy in `podcast-core::carplay`.
- [ ] CarPlay scene delegate file copied verbatim; rebinds to
      capability.

**Quality gates:**
- [ ] CarPlay simulator test: Now Playing + Listen Now + Shows +
      Downloads + Search all work.

### Unit M11.C — Widgets + Live Activity

**Tasks:**
- [ ] Widget extension reads App Group JSON snapshot file written by
      Rust (one-way mirror — kernel writes it on `now_playing`
      change).
- [ ] Live Activity: `live_activity` snapshot field; ActivityKit
      executor under capability with ≤10s update cap (R14).

**Quality gates:**
- [ ] Live Activity shows correct chapter + progress on Lock Screen.

### Unit M11.D — AppIntents + Deep links + Handoff + iCloud sync

**Tasks:**
- [ ] `Features/AppIntents/StartVoiceModeIntent.swift` — adapt to
      dispatch a Rust action.
- [ ] `Services/DeepLinkHandler.swift` ported to
      `podcast-core::deeplink`; iOS receives URL via `onOpenURL` and
      dispatches.
- [ ] `Services/HandoffActivityType.swift` →
      `podcast-core::handoff` + `Capabilities/HandoffCapability.swift`.
- [ ] `Services/iCloudSettingsSync.swift` → capability executor;
      decisions in `podcast-core::settings::icloud`.

**Quality gates:**
- [ ] Siri + voice intent works.
- [ ] Deep link to episode opens correct view.
- [ ] Handoff carries to another device.
- [ ] iCloud settings sync round-trip.

### Unit M11.E — Spotlight + Data export + Review prompt + WhatsNew

**Tasks:**
- [ ] `Capabilities/SpotlightCapability.swift` (decisions in
      `podcast-knowledge::index::spotlight_policy`).
- [ ] `Capabilities/DataExportCapability.swift` (write file; bytes
      from Rust).
- [ ] `Capabilities/ReviewPromptCapability.swift` (call
      `SKStoreReviewController`; decision in
      `podcast-core::review_prompt`).
- [ ] `Capabilities/WhatsNewBundleCapability.swift` (read bundled
      `whats-new.json`; display decision in
      `podcast-core::whatsnew`).

**Quality gates:**
- [ ] Spotlight item appears after indexing.
- [ ] Data export produces a valid JSON archive.

### Unit M11.F — Final lint sweep + remaining UI

Files (mostly already migrated; sweep for stragglers):
- `App/Sources/Features/Bookmarks/*.swift`
- `App/Sources/Features/WhatsNew/*.swift`
- `App/Sources/Features/Clippings/*.swift`
- `App/Sources/Features/Identity/*.swift` (revisit any leftovers)
- `App/Sources/Features/Settings/*.swift` (non-AI; revisit)

**Tasks:**
- [ ] Tooling for any remaining files.
- [ ] Verify lint gates pass repo-wide.

**Quality gates:**
- [ ] `ci/ui-copy-fidelity.sh` green for all migrated files.
- [ ] `ci/no-business-logic-in-swift.sh` green.

---

## Sequential integration

- [ ] Merge A–F in any compatible order. They're largely orthogonal.
- [ ] Cross-feature smoke: lock screen widget shows current episode
      that CarPlay is also playing; Spotlight find brings up the
      same episode.

---

## Exit checklist

- [ ] CarPlay works.
- [ ] Widgets + Live Activity show correct state.
- [ ] AppIntents work (voice mode start).
- [ ] Deep links route correctly.
- [ ] Spotlight index populated.
- [ ] Handoff between devices works.
- [ ] iCloud settings round-trip.
- [ ] Review prompt timing decisions in Rust.
- [ ] What's-new sheet shows entries newer than last-seen.
- [ ] Notifications fire per budget.
- [ ] **Swift files deleted:**
  - `App/Sources/CarPlay/*.swift` (all 7 — adapted, not deleted in
    file terms; but no business logic; verify lint)
  - `App/Sources/Services/SpotlightIndexer.swift` (file kept as
    capability — verify executor-only)
  - `App/Sources/Services/NotificationService.swift` (capability)
  - `App/Sources/Services/DeepLinkHandler.swift` (capability)
  - `App/Sources/Services/HandoffActivityType.swift` (capability)
  - `App/Sources/Services/iCloudSettingsSync.swift` (capability)
  - `App/Sources/Services/ReviewPrompt.swift` (capability)
  - `App/Sources/Services/DataExport.swift` (capability)
  - `App/Sources/Services/WhatsNew.swift` (capability)
- [ ] M12 unblocked.

## Hand-off to M12

M12 sweeps deletions + validates the whole repo lint-clean.
