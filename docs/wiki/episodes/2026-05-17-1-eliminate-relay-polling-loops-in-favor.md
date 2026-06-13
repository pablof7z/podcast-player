---
type: episode-card
date: 2026-05-17
session: 10228378-5073-48b1-9cd7-25b4834f2bac
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/10228378-5073-48b1-9cd7-25b4834f2bac.jsonl
salience: architecture
status: active
subjects:
  - relay-diagnostics
  - nostr-discovery
  - polling-elimination
supersedes: []
related_claims: []
source_lines:
  - 37-37
  - 255-268
  - 325-325
  - 334-352
  - 354-354
  - 488-515
captured_at: 2026-06-12T12:41:51Z
---

# Episode: Eliminate relay polling loops in favor of NDK reactive streams

## Prior State

Relay diagnostics views (NetworkingSettingsView, RelayDetailView) used 1-second polling loops (`refreshLoop()` with `Task.sleep`) to snapshot relay state, and NostrPodcastDiscoveryService used a 200ms polling loop in `ensureRelayConnected()` to wait for relay connections. A "Last refresh" timestamp was displayed to users as a proxy for data freshness.

## Trigger

User expressed strong opposition to polling ("I FUCKING HATE POLLING"), triggering an audit that found NDK already exposes `relay.stateStream: AsyncStream<State>` (emits current state immediately + future deltas) and `ndk.relayChanges: AsyncStream<NDKPoolChangeEvent>` (pool-level add/remove/connect/disconnect events).

## Decision

Replaced all NDK-related polling with reactive subscriptions: NetworkingSettingsView and RelayDetailView now subscribe to `ndk.relayChanges`; NostrPodcastDiscoveryService now races `relay.stateStream` against a 3-second timeout instead of polling. Removed `refreshedAt` from `RelayDiagnosticsSnapshot` model and the "Last refresh" UI row entirely.

## Consequences

- Views rebuild only on actual relay state changes rather than every second regardless of change
- "Last refresh" timestamp no longer exists in the UI or data model — freshness is implicit in the event-driven design
- Discovery service relay connection check returns instantly for already-connected relays (stateStream yields current state immediately) rather than polling at 200ms intervals
- All legitimate non-Nostr polling patterns (CarPlay chapter hydration, playback position persistence, RSS refresh, AssemblyAI transcript polling, etc.) were audited and left unchanged — doctrine applies specifically to Nostr/NDK connectivity

## Open Tail

*(none)*

## Evidence

- transcript lines 37-37
- transcript lines 255-268
- transcript lines 325-325
- transcript lines 334-352
- transcript lines 354-354
- transcript lines 488-515

