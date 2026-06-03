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
        // Hard rule: NO signing in Swift. The ShakeFeedbackKit protocol expects
        // a signed event returned synchronously; the compliant path is a kernel
        // sign-for-return continuation (`nmp_app_sign_event_for_return` → read
        // the `signed_events` frame), which is not wired yet. Until then we
        // surface a missing-identity error so the SDK does not publish — rather
        // than signing in Swift. See `docs/wiki/nmp-signing-contract.md`.
        _ = draft
        guard await MainActor.run(body: { identity?.publicKeyHex }) != nil else {
            throw ShakeFeedbackError.missingIdentity
        }
        throw ShakeFeedbackError.missingIdentity
    }
}
