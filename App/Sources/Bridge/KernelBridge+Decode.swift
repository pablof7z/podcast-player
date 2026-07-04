import Foundation

// ─── dispatchAction outcome ──────────────────────────────────────────────

/// Synchronous outcome of `PodcastApp.dispatchAction(envelope:)`.
enum DispatchResult: Equatable {
    /// The action was accepted and enqueued. Carries the `correlation_id`
    /// minted by `ActionRegistry::start`.
    case accepted(correlationId: String)
    /// The action was rejected synchronously. Carries a human-readable reason.
    case failure(_ message: String)

    var correlationId: String? {
        if case let .accepted(id) = self { return id }
        return nil
    }

    var errorMessage: String? {
        if case let .failure(msg) = self { return msg }
        return nil
    }

    static func from(outcome: PodcastDispatchOutcome) -> DispatchResult {
        if let message = outcome.error, !message.isEmpty {
            return .failure(message)
        }
        if let correlationId = outcome.correlationId, !correlationId.isEmpty {
            return .accepted(correlationId: correlationId)
        }
        if let code = outcome.code, !code.isEmpty {
            return .failure("dispatch returned no correlation id (code=\(code))")
        }
        return .failure("dispatch returned no correlation id")
    }
}
