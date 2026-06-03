# NMP Signing Contract (v0.2.4)

All Nostr event signing for the podcast app is owned by NMP (the kernel). No
private key ever signs in Swift, and the app's Rust crate constructs no
`nostr::Event`s for the active-account paths. This page documents the v0.2.4
FFI entry points the app relies on and the one structural gap that remains.

## v0.2.4 signing entry points

### Active-account publish (fire-and-forget)
- `nmp_app_dispatch_action(app, "nmp.publish", body)` with:
  - `{"PublishProfile": {"fields": { … }}}` — kind:0 metadata. Kernel
    serialises `fields` into the kind:0 `content`, signs with the active
    account, stamps `created_at` (D7), routes via NIP-65 outbox (D3).
  - `{"PublishRaw": {"kind": N, "tags": [...], "content": "...", "target": "Auto"}}`
    — any non-0/non-3 kind. Kernel fills `pubkey`, stamps `created_at`, signs
    with the **active** account. `target` may be `"Auto"` or
    `{"Explicit": {"relays": [...]}}` (the feedback path uses Explicit so the
    kernel performs NIP-42 AUTH on a protected relay).
- These are wrapped in `apps/nmp-app-podcast/src/nmp_dispatch.rs`:
  `publish_profile_via_nmp`, `publish_raw_via_nmp`, `publish_raw_explicit_via_nmp`.
- Consumers: `social_publish_handler` (kind:0/1/9802), `agent_note_handler`
  (kind:1), `comments_handler` (kind:1111), `feedback_handler` (explicit relay).

### Sign-in / account registration
- `nmp_app_signin_nsec(app, secret, make_active)` — `make_active = 1` activates;
  `make_active = 0` registers a non-active signer that can sign by naming its
  pubkey.
- `nmp_app_signin_bunker(app, uri, make_active)` — NIP-46 bunker; kernel owns
  the remote signer. The kernel signs for bunker accounts too, so
  `podcast.social` publishing works for `.remoteSigner` identities without any
  Swift signing.
- `nmp_app_create_new_account(app, profile_json, relays_json, mls, make_active)`
  — keypair generation + kind:0/10002 publish, kernel-side.

### Sign-and-return (no publish) — D13
- `nmp_app_sign_event_for_return(app, account_pubkey_hex, unsigned_json)` →
  returns a `correlation_id` C string. `account_pubkey_hex == ""` signs with
  the active account; a hex pubkey signs with a named (non-active) account.
- The signed flat-NIP-01 JSON is delivered **asynchronously** in the
  `signed_events` snapshot projection, keyed by the correlation id:
  `{ "ok": true, "signed_json": "…" }` or `{ "ok": false, "error": "…" }`.
- **Delivery is drain-on-emit**: `Kernel::take_signed_events_projection` clears
  the entry the first frame it is emitted. A consumer MUST register its
  continuation BEFORE dispatching and read the single carrying frame.

## Structural gap: sign-for-return is host-frame-only

`nmp_app_sign_event_for_return` delivers its result ONLY through the
`signed_events` projection frame. There is no production Rust API that reads the
live kernel `signed_events` map (`nmp_app_read_projection_json` is
`cfg(test-support)` and reads the snapshot-projection registry, not the
actor-owned map). The app's host-op handlers run ON the actor thread, and a
dispatched `SignEventForReturn` is processed on a *later* actor turn — so a
host-op cannot synchronously await a signed result without deadlocking the
actor.

Consequently the following flows cannot be expressed as pure app-Rust
fire-and-forget under v0.2.4 and are NOT yet migrated:

| Flow | Why blocked |
|---|---|
| `host_op_publish::publish_show` (kind:10154) | Signed by a **non-active** per-podcast key; no dispatchable action exposes `signer_pubkey` (`PublishRaw` hardcodes `None`). |
| `host_op_publish::publish_episode` (kind:54) | Same per-podcast key; also depends on the Blossom URL below. |
| `host_op_publish_lifecycle` deletion (kind:5) | Same per-podcast key. |
| `blossom::upload_to_blossom` (kind:24242 auth) | Needs the signed auth header **back** in-Rust for the HTTP PUT; only available via the host frame. |
| Swift avatar upload (`BlossomUploader`) | Same kind:24242 auth-header dependency. |

### Two options to close the gap (decision pending)
1. **Upstream NMP**: add `signer_pubkey: Option<String>` to the dispatchable
   `PublishRaw` action (the kernel `publish_unsigned_event` already accepts it),
   which unblocks episode/show/deletion as pure-Rust fire-and-forget; and add a
   Rust-readable sign-for-return (e.g. a blocking-with-timeout drain) for the
   Blossom auth header.
2. **Swift continuations**: register every per-podcast key as a non-active
   kernel account (`signin_nsec(make_active:0)`), then drive episode/show/
   blossom from Swift, reading the `signed_events` frame in the existing frame
   callback before the HTTP PUT. (Swift reading a kernel-signed header is not
   signing, so "NO signing in Swift" still holds.)
