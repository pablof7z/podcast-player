import Foundation

// MARK: - KernelModel sign-and-return (D13)
//
// The kernel signs an unsigned event draft with its OWN key material (active
// nsec or a NIP-46 bunker) and hands the signed JSON back through the
// `signed_events` snapshot projection — the host never reads raw private key
// bytes. This file owns the Swift half: a correlation-id-keyed continuation
// registry and the `async throws` helper callers await.
//
// ── Race contract ─────────────────────────────────────────────────────────
// `nmp_app_sign_event_for_return` RETURNS the correlation_id — it does not
// exist until after the FFI call. For a local nsec the kernel signs
// synchronously and the resulting frame can reach `apply(result:)` before this
// helper finishes registering its continuation. `signed_events` is drain-once,
// so a result that arrives before registration would be lost and the caller
// would hang forever.
//
// The registry is therefore a SYMMETRIC stash, not a plain continuation map:
//   • register: if a result is already stashed for the id → resume now; else
//     store the continuation.
//   • resolve (frame handler): if a continuation is registered → resume + remove;
//     else stash the result.
// Both halves run on `@MainActor` (this type is `@MainActor`-isolated and
// `apply` hops to the main actor before calling `resolveSignedEvents`), so the
// two-step check-then-act is atomic without an explicit lock.

extension KernelModel {

    /// Sign `unsignedJSON` with the kernel's `accountPubkeyHex` signer (pass
    /// `""` for the active account) and return the resulting flat NIP-01 event
    /// JSON. Suspends until the kernel parks the result in `signed_events` (a
    /// local key resolves on the next frame; a NIP-46 bunker after the broker
    /// responds). Throws on a kernel-reported sign failure, a dispatch failure
    /// (null id), or a Swift-side timeout.
    ///
    /// `unsignedJSON` is `{"kind":N,"content":"...","tags":[[...]],"created_at":N}`;
    /// `created_at` is advisory — the kernel re-stamps it from its own clock (D7).
    func signEventForReturn(
        accountPubkeyHex: String,
        unsignedJSON: String,
        timeout: Duration = .seconds(20)
    ) async throws -> String {
        guard let correlationID = kernel.signEventForReturn(
            accountPubkeyHex: accountPubkeyHex,
            unsignedJSON: unsignedJSON
        ) else {
            throw SignAndReturnError.dispatchFailed
        }

        // Suspend on the correlation id; a detached timeout task fails the
        // continuation if no frame ever carries the result. The Rust 5s budget
        // only covers a non-responsive NIP-46 broker (which DOES emit an error
        // verdict); a lost frame / dead actor would otherwise hang this await
        // forever — a stuck spinner the user cannot escape. Both resolution
        // paths run on MainActor and guard on `removeValue`, so whichever fires
        // first wins and the other is a no-op (no double-resume).
        return try await withCheckedThrowingContinuation { continuation in
            registerSignContinuation(correlationID: correlationID, continuation: continuation)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                failSignContinuation(
                    correlationID: correlationID,
                    error: SignAndReturnError.timedOut
                )
            }
        }
    }

    // ── Registry (stash) ────────────────────────────────────────────────────

    /// Register a continuation for `correlationID`. If the kernel already parked
    /// a result for it (the local-key fast frame beat us here), resolve now from
    /// the stash instead of waiting.
    private func registerSignContinuation(
        correlationID: String,
        continuation: CheckedContinuation<String, Error>
    ) {
        if let stashed = pendingSignResults.removeValue(forKey: correlationID) {
            Self.resume(continuation, with: stashed)
            return
        }
        signContinuations[correlationID] = continuation
    }

    /// Resolve every waiting continuation whose id appears in this frame's
    /// `signed_events` slice. An id with no registered continuation is stashed
    /// (the FFI call has not finished registering yet — drain-once means we must
    /// not drop it).
    func resolveSignedEvents(_ entries: [String: [String: Any]]) {
        for (correlationID, entry) in entries {
            let outcome = SignOutcome(entry)
            if let continuation = signContinuations.removeValue(forKey: correlationID) {
                Self.resume(continuation, with: outcome)
            } else {
                pendingSignResults[correlationID] = outcome
            }
        }
    }

    /// Fail and remove a pending continuation (Swift-side timeout). A no-op if
    /// the kernel result already resolved it.
    private func failSignContinuation(correlationID: String, error: Error) {
        if let continuation = signContinuations.removeValue(forKey: correlationID) {
            continuation.resume(throwing: error)
        }
        pendingSignResults.removeValue(forKey: correlationID)
    }

    private static func resume(
        _ continuation: CheckedContinuation<String, Error>,
        with outcome: SignOutcome
    ) {
        switch outcome {
        case .success(let signedJSON):
            continuation.resume(returning: signedJSON)
        case .failure(let message):
            continuation.resume(throwing: SignAndReturnError.kernelRejected(message))
        }
    }
}

// ── Outcome / errors ────────────────────────────────────────────────────────

/// Parsed `signed_events[<id>]` value. Keys are read VERBATIM (snake_case
/// `ok` / `signed_json` / `error`) — the raw `JSONSerialization` decode that
/// produced the dict does NOT apply `.convertFromSnakeCase`.
enum SignOutcome {
    case success(String)
    case failure(String)

    init(_ entry: [String: Any]) {
        if (entry["ok"] as? Bool) == true, let signed = entry["signed_json"] as? String {
            self = .success(signed)
        } else {
            self = .failure((entry["error"] as? String) ?? "sign-and-return failed")
        }
    }
}

enum SignAndReturnError: LocalizedError {
    /// Rust handed back a null/empty correlation id (only possible for a null
    /// app) — the kernel never saw the command.
    case dispatchFailed
    /// The kernel reported a sign failure under the correlation id.
    case kernelRejected(String)
    /// No result arrived within the Swift-side budget (lost frame / dead actor;
    /// the Rust broker-timeout path emits its own `kernelRejected` instead).
    case timedOut

    var errorDescription: String? {
        switch self {
        case .dispatchFailed: return "Could not request a signature."
        case .kernelRejected(let message): return message
        case .timedOut: return "Signing timed out."
        }
    }
}
