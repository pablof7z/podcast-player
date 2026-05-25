# M1 — Identity & Nostr foundation

**Status:** unclaimed
**Scale:** M (1–3 weeks wall)
**Depends on:** M0
**Blocks:** M2, M7, M10
**Parallel work units:** 4

---

## Scope

Bring up NIP-46 onboarding, local nsec, Keychain-backed identity,
kind:0 profile, NIP-65 relay list — all backed by NMP's existing
`nmp-signers` + `nmp-signer-broker`. iOS Identity / Onboarding /
SettingsHub Nostr surfaces render unchanged via the copy-tooling.

Also: BYOK Keychain audit (R6).

---

## Pre-flight

- [ ] M0 exit checklist complete.
- [ ] **API audit:** read
      `/home/pablo/Work/nostrmultiplatform/crates/nmp-signers/src/lib.rs`.
      Confirm `AccountManager`, `Signer` trait, NIP-46 helpers.
      Update [`../02-crates.md`](../02-crates.md) §A if stale.
- [ ] **R6 audit:** read `App/Resources/Podcastr.entitlements` and grep
      the legacy code for `kSecAttrAccessGroup` writes. Record the
      decision in the milestone notes section below.

### R6 decision (record before claiming units)

- Bundle ID for `ios/Podcast/`: ☐ `io.f7z.podcast` (preserved)  ☐ new (___)
- Legacy `kSecAttrAccessGroup` value (if any): _______
- BYOK migration path: ☐ direct read (same group)  ☐ transitional release  ☐ re-pair
- If transitional release: separate ticket filed: _______

---

## Parallel work units

### Unit M1.A — Identity Rust wiring

**Owner:** _(unclaimed)_
**Worktree:** `nostrmultiplatform-worktree-m1a/`

**Tasks:**
- [ ] In `apps/podcast/nmp-app-podcast/src/ffi/register.rs`, register
      identity defaults from `nmp-app-template`.
- [ ] Add snapshot fields `active_account`, `accounts`,
      `nip46_onboarding`, `bunker_handshake` (per
      [`../04-snapshot.md`](../04-snapshot.md)).
- [ ] Add actions: `SignInLocalNsec`, `SignInBunkerUri`,
      `CancelBunker`, `SignOut`, `SwitchAccount`, `EditProfile`,
      `PublishProfile`.

**Quality gates:**
- [ ] `cargo test -p nmp-app-podcast` (new tests cover sign-in flows).
- [ ] Doctrine lint green.

### Unit M1.B — Keychain capability extensions

**Owner:** _(unclaimed)_
**Worktree:** `podcast-worktree-m1b/`

**Tasks:**
- [ ] Add namespaces in `KeychainCapability.swift`: `pcst.identity.nsec`,
      `pcst.identity.bunker_session`, `pcst.byok.<provider>` (slots
      reserved; populated in later milestones).
- [ ] If R6 decision requires transitional release, ship a Podcastr
      app update that adds `keychain-access-groups` to entitlements
      BEFORE proceeding past this unit. That's a separate release
      branch tracked by a separate ticket.
- [ ] On first launch, the legacy Keychain reader (via new
      `nmp.legacy_io.capability` — file BACKLOG entry if not present)
      reads existing nsec / bunker session / BYOK keys and the
      migration shim re-stores them under the new namespaces.

**Quality gates:**
- [ ] Manual: run on a device with the legacy app's Keychain entries
      present; verify new app reads them.
- [ ] No business decisions in capability code (D7 audit).

### Unit M1.C — UI migration: Identity + Onboarding

**Owner:** _(unclaimed)_
**Worktree:** `podcast-worktree-m1c/`

Files to migrate via tooling:
- `App/Sources/Features/Identity/*.swift`
- `App/Sources/Features/Onboarding/*.swift`

**Tasks:**
- [ ] Run `ci/migration/copy-features.sh` for those directories.
- [ ] Run `apply-token-swap.swift` (token table covers
      `UserIdentityStore.shared.*` → `model.*`).
- [ ] Verify `ui-copy-fidelity.sh` green per file.
- [ ] Capture/match golden screenshots for: Welcome, nsec sign-in,
      bunker pair, profile setup, "skip identity" path.

**Quality gates:**
- [ ] Snapshot tests match legacy goldens (within tolerance band).
- [ ] No `class` declarations leaked into copied files.
- [ ] Lint gates green.

### Unit M1.D — UI migration: Settings Identity tab + NIP-46 sheet

**Owner:** _(unclaimed)_
**Worktree:** `podcast-worktree-m1d/`

Files:
- `App/Sources/Features/Settings/*Identity*.swift`
- `App/Sources/Features/Settings/*Nostr*.swift`

**Tasks:**
- [ ] Same procedure as M1.C.
- [ ] Verify NIP-46 pairing sheet works end-to-end against a real
      bunker (test bunker URL in
      `docs/perf/codex-reviews/...` if any; else `nsec.app` test
      deployment).

**Quality gates:**
- [ ] Bunker pair, profile read, sign-out all dispatch correctly to
      Rust and update the snapshot.

---

## Sequential integration

- [ ] Merge M1.A.
- [ ] Merge M1.B (Keychain capability).
- [ ] Merge M1.C + M1.D (UI).
- [ ] Live test against `wss://relay.damus.io`: kind:0 publish from new
      app appears.
- [ ] Live test: NIP-46 bunker pair completes against `nsec.app`.
- [ ] NIP-65 relay list published; readable from a second client.

---

## Exit checklist

- [ ] All units merged.
- [ ] Sign-in via nsec works.
- [ ] Sign-in via NIP-46 bunker works.
- [ ] kind:0 profile publishes to user's outbox.
- [ ] kind:10002 (NIP-65) relay list publishes.
- [ ] Multi-account switch works.
- [ ] BYOK Keychain entries (if any) preserved per R6 decision.
- [ ] **Swift files deleted at end:**
  - `App/Sources/Services/NIP19.swift`
  - `App/Sources/Services/Bech32.swift`
  - `App/Sources/Services/NIP65RelayFetcher.swift`
  - `App/Sources/Services/UserIdentityStore.swift`
  - `App/Sources/Services/UserIdentityStore+NIP46.swift`
  - `App/Sources/Services/UserIdentityStore+ProfileFetch.swift`
  - `App/Sources/Services/UserIdentityStore+Publishing.swift`
  - `App/Sources/Services/NostrCredentialStore.swift`
  - `App/Sources/Services/NostrKeyPair.swift`
  - `App/Sources/Services/Nip46/*.swift` (all 9 files)
  - `App/Sources/Services/NostrProfileFetcher.swift`
- [ ] No reference to any of the deleted symbols anywhere in
      `ios/Podcast/`.
- [ ] Whats-new entry (optional — likely "skip-internal" per AGENTS.md).
- [ ] M2 unblocked.

## Hand-off to M2

M2 can rely on:
- An active account exists in the snapshot.
- The user can sign in via nsec or NIP-46.
- Profile publishes work.
- NIP-65 outbox configured.
- Identity-related Swift files are gone.
