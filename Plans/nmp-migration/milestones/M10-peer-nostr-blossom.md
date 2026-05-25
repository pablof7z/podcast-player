# M10 — Peer agents + NIP-74 + Blossom + Feedback

**Status:** unclaimed
**Scale:** L
**Depends on:** M1, M7
**Blocks:** M11
**Parallel work units:** 5

---

## Scope

Brings up:
- `nmp-nip74` crate (new NMP module for podcast addressable events).
- `nmp-blossom` crate (new NMP module for media uploads).
- `podcast-peer` crate (NIP-10 thread reconstruction via
  `nmp-threading`, allow-list, pending approvals).
- `podcast-discovery::nostr` (publish/discovery via `nmp-nip74`).
- `podcast-feedback` (FeedbackStore relay client → Rust per Sonnet
  review finding R4).

---

## Pre-flight

- [ ] M1 + M7 exits green.
- [ ] BACKLOG `nmp-nip74-add`, `nmp-blossom`, possibly `nmp-nip26-add`
      landed.
- [ ] R5 confirmed: `nmp-threading` API fits `podcast-peer` needs.
      Extend in BACKLOG if not.
- [ ] R12 ADR for NIP-74 schema pinning landed.

---

## Parallel work units

### Unit M10.A — `nmp-nip74` crate

**Tasks:**
- [ ] New crate per `02-crates.md` §B.
- [ ] Publish + query actions; event views.
- [ ] ADR pinning kinds 30074/30075 + tag layout.

**Quality gates:**
- [ ] `cargo test -p nmp-nip74` round-trip.
- [ ] Live test publishing to `wss://relay.damus.io` and reading back.

### Unit M10.B — `nmp-blossom` crate

**Tasks:**
- [ ] New crate for Blossom protocol (multi-part upload).
- [ ] Auth via Nostr event signing (kind:24242 per spec).

**Quality gates:**
- [ ] Live test against `https://blossom.primal.net` or similar.

### Unit M10.C — `podcast-peer` crate

**Tasks:**
- [ ] Uses `nmp-threading` for NIP-10 reconstruction (no duplicate
      grouper).
- [ ] Allow-list + pending approval state.
- [ ] Peer-agent inbox: NIP-17 DMs (gift-wrapped) drive turns through
      `podcast-agent-core` with the peer's prompt context.
- [ ] NIP-26 delegation if required.

**Quality gates:**
- [ ] Unit tests for allow-list policy + approval flow.
- [ ] Live test: two devices, one approves the other, message flow
      works.

### Unit M10.D — `podcast-discovery::nostr` + `podcast-feedback`

**Tasks:**
- [ ] `podcast-discovery::nostr::{publish, discover}` orchestrates
      `nmp-nip74`.
- [ ] `podcast-feedback` crate: feedback relay URL
      (`wss://relay.tenex.chat`) is a `DomainModule` field;
      publishes feedback events via `nmp-nip01` SendNote on that
      relay (R4).
- [ ] R4 fix: `FeedbackStore`'s legacy independent WebSocket is
      replaced by an NMP relay-pool entry scoped to the feedback URL.

**Quality gates:**
- [ ] Feedback submission lands on `wss://relay.tenex.chat` and
      appears in the legacy app's feedback browser.

### Unit M10.E — iOS UI migration: Friends, Feedback, Conversations

Files:
- `App/Sources/Features/Friends/*.swift`
- `App/Sources/Features/Feedback/*.swift`
- Split: `FeedbackStore.swift` (369 LOC; class + FeedbackRelayClient
  excised).
- Threading (`App/Sources/Features/Threading/*.swift`).

**Tasks:**
- [ ] Tooling: copy → split → token-swap.
- [ ] Bind to `friends`, `pending_approvals`, `nostr_conversations`,
      `feedback` projections.

**Quality gates:**
- [ ] Goldens match.

---

## Sequential integration

- [ ] Merge M10.A first (NIP-74 crate).
- [ ] Merge M10.B (Blossom — independent; can land in parallel).
- [ ] Merge M10.C (peer crate; depends on `nmp-threading` + NIP-17).
- [ ] Merge M10.D (discovery + feedback).
- [ ] Merge M10.E (UI).
- [ ] Cross-device live test for peer agent.
- [ ] Publish + discover a NIP-74 podcast on two devices.

---

## Exit checklist

- [ ] Peer-agent inbox works end-to-end.
- [ ] NIP-74 publish + discover work.
- [ ] Blossom upload works for at least clip-audio attachments.
- [ ] Feedback relay submission works (R4 resolved).
- [ ] **Swift files deleted:**
  - `App/Sources/Services/NostrAgentResponder.swift`,
    `NostrAgentResponder+Delegation.swift`
  - `App/Sources/Services/NostrPodcastDiscoveryService.swift`,
    `NostrPodcastPublisher.swift`
  - `App/Sources/Services/NostrCommentService.swift`
  - `App/Sources/Services/NostrEventPublisher.swift`
  - `App/Sources/Services/NostrThreadFetcher.swift`
  - `App/Sources/Services/NostrRelayService.swift`
  - `App/Sources/Services/BlossomUploader.swift`
  - `App/Sources/Features/Feedback/FeedbackStore.swift` (class)
  - `App/Sources/Agent/AgentRelayBridge.swift`
  - `App/Sources/Agent/NostrPeerAgentPrompt.swift`
  - `App/Sources/Agent/LivePeerEventPublisher.swift`
- [ ] M11 unblocked.

## Hand-off to M11

M11 can rely on: NIP-74 publishing for owned-podcast feature;
peer-agent inbox + friends; Blossom upload available for clip share.
