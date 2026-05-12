import Foundation

// MARK: - Peer conversation ended-roots

extension AppStateStore {

    /// Marks a peer-conversation root as ended by the agent. Idempotent —
    /// repeated calls for the same `rootEventID` are no-ops. Drives UI
    /// affordances (e.g. "agent has signed off") and prevents downstream
    /// turn-handlers from drafting further outbound replies.
    func markPeerConversationEnded(rootEventID: String) {
        guard !rootEventID.isEmpty else { return }
        state.nostrEndedRootIDs.insert(rootEventID)
    }

    /// `true` iff the agent has explicitly ended this conversation root via
    /// the `end_conversation` tool.
    func isPeerConversationEnded(rootEventID: String) -> Bool {
        state.nostrEndedRootIDs.contains(rootEventID)
    }
}
