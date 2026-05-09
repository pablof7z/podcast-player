import Foundation

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

    func dismissNostrPendingApproval(_ id: UUID) {
        state.nostrPendingApprovals.removeAll { $0.id == id }
    }

    var pendingNostrApprovals: [NostrPendingApproval] {
        state.nostrPendingApprovals
    }
}
