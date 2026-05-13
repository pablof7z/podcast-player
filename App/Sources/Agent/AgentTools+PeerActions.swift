import Foundation

// MARK: - Peer-conversation tool surface
//
// Ported from win-the-day's `end_conversation` and `send_friend_message`. Both
// tools are peer-only: when the dispatch has no `peerContext` they early-return
// a clean `toolError`, since calling them outside a Nostr peer turn has no
// well-defined effect.

extension AgentTools {

    // MARK: - end_conversation

    static func endConversationTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let peerContext = deps.peerContext else {
            return toolError("end_conversation requires a peer conversation context")
        }
        guard let reason = (args["reason"] as? String)?.trimmed, !reason.isEmpty else {
            return toolError("Missing or empty 'reason'")
        }
        return toolSuccess([
            "no_reply": true,
            "reason": reason,
            "root_event_id": peerContext.rootEventID,
        ])
    }

    // MARK: - send_friend_message

    /// Publish a kind:1 note p-tagged at a named friend. Per the current
    /// design (mirroring win-the-day's `.peerAgent` channel), this tool is
    /// peer-only — calling it outside a peer conversation returns a clean
    /// tool error. Inside a peer turn, the reply is threaded under the
    /// active conversation root via NIP-10 tags.
    static func sendFriendMessageTool(args: [String: Any], deps: PodcastAgentToolDeps) async -> String {
        guard let peerContext = deps.peerContext else {
            return toolError("send_friend_message requires a peer conversation context")
        }
        guard let friendPubkey = (args["friend_pubkey"] as? String)?.trimmed, !friendPubkey.isEmpty else {
            return toolError("Missing or empty 'friend_pubkey'")
        }
        guard let message = (args["message"] as? String)?.trimmed, !message.isEmpty else {
            return toolError("Missing or empty 'message'")
        }
        // Gate on the user's local Friends list so the agent cannot fire
        // kind:1 events at arbitrary pubkeys on the user's identity.
        let known = await deps.friendDirectory.isKnownFriend(pubkeyHex: friendPubkey)
        guard known else {
            return toolError("Pubkey '\(friendPubkey)' is not in your Friends list. Add them first.")
        }
        do {
            let eventID = try await deps.peerPublisher.publishFriendMessage(
                friendPubkeyHex: friendPubkey,
                body: message,
                peerContext: peerContext
            )
            return toolSuccess([
                "event_id": eventID,
                "friend_pubkey": friendPubkey,
                "root_event_id": peerContext.rootEventID,
            ])
        } catch {
            return toolError("send_friend_message failed: \(error.localizedDescription)")
        }
    }
}
