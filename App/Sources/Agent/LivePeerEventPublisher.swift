import Foundation
import os.log

// MARK: - LivePeerEventPublisher
//
// Dispatches kind:1 agent-to-agent notes through the Rust kernel.
// Swift passes typed semantic values; Rust builds NIP-10 tags and routes via NMP.

final class LivePeerEventPublisher: PeerEventPublisherProtocol, @unchecked Sendable {
    weak var store: AppStateStore?

    init(store: AppStateStore) { self.store = store }

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
            store.kernelPublishAgentNote(
                recipientPubkeyHex: peerContext.peerPubkeyHex,
                content: body,
                rootEventID: peerContext.rootEventID,
                inboundEventID: peerContext.inboundEventID,
                rootATags: peerContext.rootATags.compactMap { $0.count > 1 ? $0[1] : nil }
            )
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
            store.kernelPublishAgentNote(
                recipientPubkeyHex: friendPubkeyHex,
                content: body,
                rootATags: peerContext?.rootATags.compactMap { $0.count > 1 ? $0[1] : nil }
                    ?? [FeedbackRelayClient.projectCoordinate]
            )
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
        await MainActor.run { [weak self] in self?.store?.registerPendingFriendMessage(message) }
    }
}
