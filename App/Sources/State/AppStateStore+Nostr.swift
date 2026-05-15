import Foundation
import os.log

// MARK: - Rust core app-state observer wiring
//
// The Rust `PodcastrCore` emits app-scoped deltas (subscription_id == 0)
// for SIGNER state transitions and RELAY connection status changes. This
// extension forwards those into Swift app state so SwiftUI surfaces can
// react.
//
// FIXME(rust-cutover): `AppStateStore.init` (in `AppStateStore.swift`,
// outside this file's edit scope) must call `installNostrAppObservers()`
// exactly once after the store finishes booting. Until that wiring lands,
// the closure below is registered but never invoked.
//
// FIXME(rust-cutover): `AppState` does not yet declare `signerStatus` or
// `relayDiagnostics`. The delta handlers below log every transition via
// `os.Logger` so nothing is silently dropped while those fields are being
// added. Once the storage exists, replace the `Self.logger.info(…)` lines
// with the actual mutations described in the task brief:
//   .signerConnected(pubkey)         → state.signerStatus = .connected(pubkey)
//   .signerDisconnected(reason)      → state.signerStatus = .disconnected(reason)
//   .relayStatusChanged(url, state)  → state.relayDiagnostics[url] = mapped
//
// Note on the observer token: `PodcastrCoreBridge.addAppObserver` returns
// a `UInt64` cleanup token. Extensions can't add stored properties, so
// the token is intentionally discarded — the store lives the full app
// lifetime and the bridge is a process-wide singleton, so the observer
// never needs to be torn down. If a future test harness needs a clean
// teardown, hoist the token onto `AppStateStore.swift` (out-of-scope here).

private let nostrObserverLogger = Logger.app("AppStateStore.NostrObserver")

extension AppStateStore {

    /// Wire the app-scoped Rust delta observer. Must be invoked once from
    /// `AppStateStore.init` after the store finishes booting.
    /// FIXME(rust-cutover): call site missing — see file-level FIXME.
    func installNostrAppObservers() {
        _ = PodcastrCoreBridge.shared.addAppObserver { [weak self] delta in
            // The bridge already hopped to MainActor before invoking us,
            // so direct state access is safe.
            MainActor.assumeIsolated {
                self?.handleNostrAppDelta(delta)
            }
        }
    }

    /// Routes a single app-scoped Rust delta into Swift state. Called
    /// only from the observer closure registered in
    /// `installNostrAppObservers()`. Unrelated change cases (peer
    /// messages, comments, profile updates, …) are routed to per-
    /// subscription handlers by `PodcastrCoreBridge` and never reach
    /// this method.
    private func handleNostrAppDelta(_ delta: Delta) {
        switch delta.change {
        case .signerConnected(let pubkey):
            // FIXME(rust-cutover): wire `state.signerStatus = .connected(pubkey)` once the field lands on AppState.
            nostrObserverLogger.info("signerConnected pubkey=\(pubkey, privacy: .public)")

        case .signerDisconnected(let reason):
            // FIXME(rust-cutover): wire `state.signerStatus = .disconnected(reason)` once the field lands on AppState.
            nostrObserverLogger.info("signerDisconnected reason=\(reason, privacy: .public)")

        case .relayStatusChanged(let url, let relayState):
            // FIXME(rust-cutover): wire `state.relayDiagnostics[url] = mapped` once the field lands on AppState.
            nostrObserverLogger.info(
                "relayStatusChanged url=\(url, privacy: .public) state=\(String(describing: relayState), privacy: .public)"
            )

        default:
            // All non-app-scoped change cases are routed to per-subscription
            // handlers by the bridge. Hitting this arm would mean either
            // (a) the bridge mis-routed a subscription_id != 0 delta to
            // app observers, or (b) a new app-scoped DataChangeType case
            // was added on the Rust side without updating this switch.
            // FIXME(rust-cutover): if new app-scoped DataChangeType cases
            // are added, extend the switch.
            break
        }
    }
}

// MARK: - Nostr Access Control

extension AppStateStore {

    func allowNostrPubkey(_ pubkeyHex: String) {
        state.nostrAllowedPubkeys.insert(pubkeyHex)
        state.nostrBlockedPubkeys.remove(pubkeyHex)
        state.nostrPendingApprovals.removeAll { $0.pubkeyHex == pubkeyHex }
    }

    func blockNostrPubkey(_ pubkeyHex: String) {
        state.nostrBlockedPubkeys.insert(pubkeyHex)
        state.nostrAllowedPubkeys.remove(pubkeyHex)
        state.nostrPendingApprovals.removeAll { $0.pubkeyHex == pubkeyHex }
    }

    func removeFromNostrAllowlist(_ pubkeyHex: String) {
        state.nostrAllowedPubkeys.remove(pubkeyHex)
    }

    func removeFromNostrBlocklist(_ pubkeyHex: String) {
        state.nostrBlockedPubkeys.remove(pubkeyHex)
    }

    func addNostrPendingApproval(_ approval: NostrPendingApproval) {
        guard !state.nostrAllowedPubkeys.contains(approval.pubkeyHex),
              !state.nostrBlockedPubkeys.contains(approval.pubkeyHex),
              !state.nostrPendingApprovals.contains(where: { $0.pubkeyHex == approval.pubkeyHex })
        else { return }
        state.nostrPendingApprovals.append(approval)
    }

    /// Fills in display name / about / picture for an existing pending
    /// approval when a kind:0 profile arrives after the inbound has been
    /// queued. No-op when the pubkey is not pending.
    func enrichNostrPendingApproval(pubkeyHex: String, from profile: NostrProfileMetadata) {
        guard let idx = state.nostrPendingApprovals.firstIndex(where: { $0.pubkeyHex == pubkeyHex })
        else { return }
        var approval = state.nostrPendingApprovals[idx]
        approval.displayName = profile.bestLabel ?? approval.displayName
        approval.about = profile.about ?? approval.about
        approval.pictureURL = profile.picture ?? approval.pictureURL
        state.nostrPendingApprovals[idx] = approval
    }

    func dismissNostrPendingApproval(_ id: UUID) {
        state.nostrPendingApprovals.removeAll { $0.id == id }
    }

    var pendingNostrApprovals: [NostrPendingApproval] {
        state.nostrPendingApprovals
    }

    // MARK: - Nostr Conversations

    /// Appends `turn` to the conversation with `rootEventID`, creating the
    /// record on first sight. `counterparty` is required for the create
    /// path when the turn is outgoing (the agent's own pubkey is not the
    /// counterparty); for incoming turns `turn.pubkey` is used.
    func recordNostrTurn(
        rootEventID: String,
        turn: NostrConversationTurn,
        counterpartyPubkey: String? = nil
    ) {
        if let idx = state.nostrConversations.firstIndex(where: { $0.rootEventID == rootEventID }) {
            if !state.nostrConversations[idx].turns.contains(where: { $0.eventID == turn.eventID }) {
                state.nostrConversations[idx].turns.append(turn)
            }
            state.nostrConversations[idx].lastTouched = Date()
        } else {
            let resolved = counterpartyPubkey ?? turn.pubkey
            state.nostrConversations.append(
                NostrConversationRecord(
                    rootEventID: rootEventID,
                    counterpartyPubkey: resolved,
                    firstSeen: Date(),
                    lastTouched: Date(),
                    turns: [turn]
                )
            )
        }
    }

    /// Surfaces (or refreshes) the floating "Talking to X" capsule for the
    /// configured `nostrActivityIndicatorDuration`. Called by
    /// `NostrAgentResponder` after every incoming or outgoing turn so a
    /// back-and-forth keeps the capsule continuously on screen instead of
    /// flickering between turns.
    func noteNostrActivity(counterpartyPubkey: String) {
        activeNostrCounterparty = counterpartyPubkey
        nostrActivityDismissTask?.cancel()
        nostrActivityDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppStateStore.nostrActivityIndicatorDuration))
            guard !Task.isCancelled else { return }
            self?.activeNostrCounterparty = nil
        }
    }

    /// Inserts or upgrades a cached profile. Older `kind:0` events are
    /// ignored so a relay re-delivery never downgrades a fresher profile.
    func setNostrProfile(_ profile: NostrProfileMetadata) {
        if let existing = state.nostrProfileCache[profile.pubkey],
           existing.fetchedFromCreatedAt >= profile.fetchedFromCreatedAt {
            return
        }
        state.nostrProfileCache[profile.pubkey] = profile
    }
}
