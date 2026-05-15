import Foundation
@preconcurrency import NDKSwiftCore
import os.log

// MARK: - NostrCommentService
//
// Standalone service for NIP-22 (kind 1111) comments anchored to NIP-73
// external content identifiers. Each `subscribe(target:)` call attaches a
// fresh NDKSubscription to the shared `NDK` instance owned by
// `NostrStack.shared`. Multiple in-flight subscriptions are supported —
// each one gets its own backing `AsyncStream`. Reactive: NDK pushes
// matching events through its AsyncStream of batches; no polling or
// reconnect loops in this file.
//
// Publish path goes through whatever `NostrSigner` the caller hands in —
// `UserIdentityStore.signer` resolves to a `LocalKeySigner` or a
// `RemoteSigner` (NIP-46), so this service stays agnostic to where the
// user's key lives.
//
// NIP-22 wire shape (top-level comment on external content):
//   kind: 1111
//   content: "<plain text>"
//   tags: [
//     ["I", "<root nip73 identifier>"],
//     ["K", "<root nip73 kind>"],
//     ["i", "<parent nip73 identifier>"],   // == "I" for top-level
//     ["k", "<parent nip73 kind>"],         // == "K" for top-level
//   ]
//
// We omit reply tags (uppercase E/K of the parent comment) — phase 1
// supports top-level comments only.
@MainActor
final class NostrCommentService {

    nonisolated private static let logger = Logger.app("NostrCommentService")

    // MARK: - Wire constants

    private enum Wire {
        static let kindComment = 1111
        /// Hard cap on per-target backlog returned by the relay. The
        /// limit is also the NDKFilter limit so the relay can short-circuit.
        static let backfillLimit = 200
    }

    // MARK: - Subscription handle

    /// Returned to the caller so they can cancel the subscription when the
    /// view disappears. Holding the handle keeps the NDK subscription alive.
    final class Subscription {
        let stream: AsyncStream<EpisodeComment>
        private let cancelClosure: @Sendable () -> Void
        init(stream: AsyncStream<EpisodeComment>, cancel: @escaping @Sendable () -> Void) {
            self.stream = stream
            self.cancelClosure = cancel
        }
        func cancel() { cancelClosure() }
        deinit { cancelClosure() }
    }

    // MARK: - Deps

    private let relayURLProvider: @MainActor () -> URL?

    init(relayURLProvider: @MainActor @escaping () -> URL?) {
        self.relayURLProvider = relayURLProvider
    }

    /// Convenience initializer that reads the relay URL from
    /// `AppStateStore.state.settings.nostrRelayURL`. Use this everywhere
    /// except tests; injection above stays for unit-test wiring.
    convenience init(store: AppStateStore) {
        self.init(relayURLProvider: {
            let raw = store.state.settings.nostrRelayURL
            return raw.isEmpty ? nil : URL(string: raw)
        })
    }

    // MARK: - Subscribe

    /// Opens an NDK subscription for `target` and yields each matching
    /// comment into the returned stream. The subscription stays open
    /// (`closeOnEose: false`) until the caller cancels via the returned
    /// `Subscription` handle. NDK handles relay reconnection internally,
    /// so this method does not run a reconnect loop.
    func subscribe(target: CommentTarget) -> Subscription {
        let (stream, continuation) = AsyncStream<EpisodeComment>.makeStream(bufferingPolicy: .unbounded)

        guard let ndk = NostrStack.shared.ndk else {
            Self.logger.info("subscribe: no NDK available; finishing stream immediately")
            continuation.finish()
            return Subscription(stream: stream, cancel: { })
        }

        // Restrict the subscription to the user's configured relay (if any)
        // so this stays parity with the previous single-relay subscribe
        // semantic. Without an explicit set, NDK would fan out across the
        // whole pool which would surface unrelated comments faster but mix
        // sources the UI currently assumes are one-relay.
        let relays: Set<RelayURL>? = relayURLProvider().map { [$0.absoluteString] }
        let filter = NDKFilter(
            kinds: [Wire.kindComment],
            limit: Wire.backfillLimit,
            tags: ["i": Set([target.nip73Identifier])]
        )
        let ndkSubscription = ndk.subscribe(
            filter: filter,
            relays: relays,
            subscriptionId: "cmt-\(UUID().uuidString.prefix(8))",
            closeOnEose: false
        )

        let captured = target
        let drainTask = Task { @MainActor [weak self] in
            var seenIDs: Set<String> = []
            for await batch in ndkSubscription.events {
                guard !Task.isCancelled else { break }
                for event in batch {
                    guard event.kind == Wire.kindComment,
                          !seenIDs.contains(event.id) else { continue }
                    seenIDs.insert(event.id)
                    let comment = EpisodeComment(
                        id: event.id,
                        target: captured,
                        authorPubkeyHex: event.pubkey,
                        content: event.content,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt))
                    )
                    continuation.yield(comment)
                }
                _ = self // keep service alive for the lifetime of the drain
            }
            continuation.finish()
        }

        return Subscription(stream: stream, cancel: {
            drainTask.cancel()
            Task { await ndkSubscription.close() }
        })
    }

    // MARK: - Publish

    /// Sign a NIP-22 comment for `target` with the supplied signer, then
    /// publish it to the user's relay. Returns the signed event so the UI
    /// can optimistically append before the relay echoes it back through a
    /// live subscription.
    func publish(
        content: String,
        target: CommentTarget,
        signer: any NostrSigner
    ) async throws -> SignedNostrEvent {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PublishError.emptyContent }
        guard let url = relayURLProvider() else { throw PublishError.noRelayConfigured }

        let identifier = target.nip73Identifier
        let kindTag = target.nip73Kind
        // Top-level comment: parent (`i`/`k`) == root (`I`/`K`).
        let tags: [[String]] = [
            ["I", identifier],
            ["K", kindTag],
            ["i", identifier],
            ["k", kindTag],
        ]
        let draft = NostrEventDraft(kind: Wire.kindComment, content: trimmed, tags: tags)
        let event = try await signer.sign(draft)

        try await publishSignedEvent(event, to: url)
        return event
    }

    private func publishSignedEvent(_ event: SignedNostrEvent, to url: URL) async throws {
        // The publish path now routes through the shared `NDK` instance
        // owned by `NostrStack.shared`. NDK's `publish(event, to:)` reuses
        // the existing relay pool and adds + connects the target relay if
        // it isn't already in the pool, so we no longer open a transient
        // WebSocket per comment. The target URL is preserved verbatim from
        // the caller (user's configured relay) to keep semantics identical:
        // a top-level comment goes to the user's single relay, not to NDK's
        // outbox.
        guard let ndk = await NostrStack.shared.ndk else {
            throw PublishError.noRelayConfigured
        }
        let target = url.absoluteString
        do {
            let accepted = try await ndk.publish(NDKEventConverter.toNDKEvent(event), to: [target])
            if accepted.isEmpty {
                // NDK returned without an OK from the relay — could be a
                // queued offline publish or a silent relay drop. Old code
                // logged "no ack within 3s; assuming success" in this case;
                // preserve that optimistic UX (the UI has already appended
                // the comment) and don't throw.
                Self.logger.notice("publish: \(event.id.prefix(8), privacy: .public) → \(target, privacy: .public): no ack yet; assuming success")
            } else {
                Self.logger.info("publish: \(event.id.prefix(8), privacy: .public) → \(target, privacy: .public) ✓")
            }
        } catch {
            Self.logger.error("publish: \(event.id.prefix(8), privacy: .public) → \(target, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw PublishError.relayRejected(error.localizedDescription)
        }
    }

    // MARK: - Errors

    enum PublishError: LocalizedError {
        case emptyContent
        case noRelayConfigured
        case relayRejected(String)

        var errorDescription: String? {
            switch self {
            case .emptyContent:        "Comment is empty."
            case .noRelayConfigured:   "Set a Nostr relay URL in Settings before commenting."
            case .relayRejected(let m): "Relay rejected the comment: \(m)"
            }
        }
    }
}
