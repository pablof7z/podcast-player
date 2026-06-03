import Foundation
import ShakeFeedbackKit

extension ShakeFeedbackConfig {
    static let podcastr = ShakeFeedbackConfig(
        appName: "Pod0",
        clientTag: "podcastr-ios",
        projectATag: "31933:09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7:podcast"
    )
}

struct PodcastShakeFeedbackSigner: ShakeFeedbackSigner, @unchecked Sendable {
    weak var identity: UserIdentityStore?

    var publicKeyHex: String? {
        get async {
            await MainActor.run { identity?.publicKeyHex }
        }
    }

    func signFeedbackEvent(_ draft: ShakeFeedbackEventDraft) async throws -> ShakeFeedbackEvent {
        // D13: sign through the kernel (active account) instead of reading raw
        // private key bytes via `identity.signer`. Works for NIP-46 bunker users
        // — the old `signer.sign` path could not.
        guard let kernel = await MainActor.run(body: { identity?.kernel }),
              await MainActor.run(body: { identity?.publicKeyHex }) != nil
        else {
            throw ShakeFeedbackError.missingIdentity
        }
        let unsignedJSON = try Self.unsignedJSON(from: draft)
        // Empty pubkey → active account. The kernel fills pubkey + re-stamps
        // created_at (D7) and returns the flat NIP-01 event JSON.
        let signedJSON = try await kernel.signEventForReturn(
            accountPubkeyHex: "",
            unsignedJSON: unsignedJSON
        )
        return try Self.shakeFeedbackEvent(fromSignedJSON: signedJSON)
    }

    /// Serialize a feedback draft into the `{kind, content, tags, created_at}`
    /// shape `nmp_app_sign_event_for_return` accepts.
    private static func unsignedJSON(from draft: ShakeFeedbackEventDraft) throws -> String {
        let object: [String: Any] = [
            "kind": draft.kind,
            "content": draft.content,
            "tags": draft.tags,
            "created_at": draft.createdAt,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ShakeFeedbackError.missingIdentity
        }
        return json
    }

    /// Parse the kernel's flat NIP-01 signed-event JSON into a `ShakeFeedbackEvent`.
    private static func shakeFeedbackEvent(fromSignedJSON json: String) throws -> ShakeFeedbackEvent {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let pubkey = object["pubkey"] as? String,
              let createdAt = object["created_at"] as? Int,
              let kind = object["kind"] as? Int,
              let tags = object["tags"] as? [[String]],
              let content = object["content"] as? String,
              let sig = object["sig"] as? String
        else {
            throw ShakeFeedbackError.missingIdentity
        }
        return ShakeFeedbackEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }
}
