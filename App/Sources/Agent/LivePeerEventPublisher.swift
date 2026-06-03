import Foundation
import os.log

// MARK: - LivePeerEventPublisher
//
// Dispatches kind:1 agent-to-agent notes to the Rust kernel. Swift passes
// semantic values; Rust builds all NIP-10 tags and routes through NMP.

final class LivePeerEventPublisher: PeerEventPublisherProtocol, @unchecked Sendable {
    private let logger = Logger.app("AgentTools")
    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    func publishConversationReply(
        peerContext: PeerConversationContext,
        body: String,
        extraTags: [[String]]
    ) async throws -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NostrEventPublisherError.encodingFailed
        }
        guard let store else { throw NostrEventPublisherError.noSigningKey }
        await MainActor.run {
            store.kernelDispatch("podcast", [
                "op": "publish_agent_note",
                "recipient_pubkey_hex": peerContext.peerPubkeyHex,
                "content": body,
                "root_event_id": peerContext.rootEventID,
                "inbound_event_id": peerContext.inboundEventID,
                "root_a_tags": peerContext.rootATags.compactMap { $0.count > 1 ? $0[1] : nil }
            ])
        }
        return "queued"
    }

    func publishFriendMessage(
        friendPubkeyHex: String,
        body: String,
        peerContext: PeerConversationContext?
    ) async throws -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NostrEventPublisherError.encodingFailed
        }
        guard let store else { throw NostrEventPublisherError.noSigningKey }
        await MainActor.run {
            store.kernelDispatch("podcast", [
                "op": "publish_agent_note",
                "recipient_pubkey_hex": friendPubkeyHex,
                "content": body,
                "root_a_tags": peerContext?.rootATags.compactMap { $0.count > 1 ? $0[1] : nil }
                    ?? [FeedbackRelayClient.projectCoordinate]
            ])
        }
        return "queued"
    }
}

// MARK: - LiveFriendDirectoryAdapter

struct LiveFriendDirectoryAdapter: FriendDirectoryProtocol {
    weak var store: AppStateStore?

    init(store: AppStateStore) { self.store = store }

    func resolvePubkey(prefixOrFull: String) async -> String? {
        let needle = prefixOrFull.lowercased()
        let friends: [Friend] = await MainActor.run { store?.state.friends ?? [] }
        return friends.first { $0.identifier.lowercased().hasPrefix(needle) }?.identifier
    }
}

// MARK: - LivePendingFriendMessageRegistrar

final class LivePendingFriendMessageRegistrar: PendingFriendMessageRegistrarProtocol, @unchecked Sendable {
    weak var store: AppStateStore?

    init(store: AppStateStore) { self.store = store }

    func register(_ message: PendingFriendMessage) async {
        await MainActor.run { [weak self] in
            self?.store?.registerPendingFriendMessage(message)
        }
    }
}
