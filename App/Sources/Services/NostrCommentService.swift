import Foundation
import os.log

// MARK: - NostrCommentService
//
// NIP-22 (kind:1111) comment surface anchored to NIP-73 external content
// identifiers. After the Rust-core cutover this file is a thin Swift
// adapter around `PodcastrCoreBridge`: subscriptions and publishes both
// route through the shared `PodcastrCore` instance, which owns the relay
// pool and the active session signer.
//
// Public API surface is intentionally identical to the original
// WebSocket-backed implementation so callers in `EpisodeCommentsSection`
// (and existing tests) keep compiling without edits. The bodies, however,
// no longer touch WebSockets directly — every Nostr round-trip goes
// through the bridge.
//
// NIP-22 wire shape (top-level comment on external content) is
// constructed inside Rust now — Swift only hands over the anchor and the
// content string.
@MainActor
final class NostrCommentService {

    nonisolated private static let logger = Logger.app("NostrCommentService")

    // MARK: - Subscription handle

    /// Returned to the caller so they can cancel the subscription when
    /// the view disappears. Holding the handle keeps the underlying
    /// Rust-side subscription open.
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

    // MARK: - Per-subscription state
    //
    // `subscribe(target:)` must return synchronously, but the Rust
    // `subscribeComments(...)` call is async and only yields the
    // relay-side sub id after a round-trip. We register the delta
    // handler immediately, kick off the subscribe in a Task, and track
    // the lifecycle here so a `.cancel()` that fires before the relay
    // sub id arrives still tears down correctly once it does.
    private final class Session {
        let callbackID: UInt64
        let target: CommentTarget
        let continuation: AsyncStream<EpisodeComment>.Continuation
        var handle: PodcastrCoreBridge.SubscriptionHandle?
        /// Relay-side subscription id returned by Rust. `nil` until the
        /// async `subscribeComments` round-trip completes.
        var relaySubID: String?
        /// `true` if `.cancel()` ran before `relaySubID` was assigned.
        /// The kickoff task observes this and unsubscribes immediately
        /// once the relay id is known.
        var cancelled: Bool = false
        /// Dedup ring — relays can replay the same event across leg
        /// reconnects inside the Rust pool, but in practice the core
        /// already de-dups; this is belt-and-braces.
        var seenIDs: Set<String> = []

        init(callbackID: UInt64, target: CommentTarget, continuation: AsyncStream<EpisodeComment>.Continuation) {
            self.callbackID = callbackID
            self.target = target
            self.continuation = continuation
        }
    }

    // MARK: - Deps

    /// The relay-URL provider is kept for source compatibility with the
    /// pre-cutover initialiser shape (and the `init(store:)` convenience
    /// reads it from settings) but the Rust core owns the actual relay
    /// pool now. We still consult it as a UX gate so callers get a
    /// `noRelayConfigured` error when the user hasn't picked a relay,
    /// matching the original behaviour.
    private let relayURLProvider: @MainActor () -> URL?
    /// Active sessions keyed by callback id. The cancel closure
    /// captures only the `UInt64` callback id (Sendable) and a weak
    /// service reference, so `Session` itself never crosses an actor
    /// boundary.
    private var sessions: [UInt64: Session] = [:]

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

    /// Open a comment subscription for `target`. Returns a handle whose
    /// `stream` yields each `EpisodeComment` as it arrives. Cancelling
    /// (or releasing) the handle closes the underlying Rust
    /// subscription and unregisters from the bridge.
    ///
    /// Implementation:
    /// 1. Register a delta handler on the bridge synchronously to lock
    ///    in the callback id — this gives us a stable `UInt64` we can
    ///    hand to Rust before the async subscribe call completes.
    /// 2. Kick off a Task that calls
    ///    `core.subscribeComments(anchor:callbackSubscriptionId:)`. The
    ///    returned `String` is the relay-side sub id used for
    ///    `unsubscribeComments`.
    /// 3. If the caller cancels before step 2 finishes, the kickoff
    ///    task notices the `cancelled` flag and immediately
    ///    unsubscribes once Rust hands back the id.
    func subscribe(target: CommentTarget) -> Subscription {
        let (stream, continuation) = AsyncStream<EpisodeComment>.makeStream(bufferingPolicy: .unbounded)

        // Synchronous bridge registration first — we need the callback
        // id to pass to Rust below.
        let bridge = PodcastrCoreBridge.shared
        let handle = bridge.register { [weak self] delta in
            // Bridge already hops to MainActor before invoking us, but
            // the closure signature itself isn't actor-isolated — assert
            // the isolation so we can call MainActor-bound methods.
            MainActor.assumeIsolated {
                self?.handleDelta(delta)
            }
        }

        let session = Session(callbackID: handle.callbackID, target: target, continuation: continuation)
        session.handle = handle
        sessions[handle.callbackID] = session

        // Async kickoff: open the relay-side subscription. If `.cancel()`
        // fires while this is in flight, the kickoff observes the
        // `cancelled` flag once the relay id is known and tears down.
        let anchor = Self.anchor(for: target)
        let callbackID = handle.callbackID
        Task { @MainActor [weak self] in
            do {
                let relaySubID = try await bridge.core.subscribeComments(
                    anchor: anchor,
                    callbackSubscriptionId: callbackID
                )
                guard let self else {
                    // Service deallocated while we were awaiting — tear
                    // down the relay subscription and bail. Capture the
                    // (Sendable) `core` handle into the detached Task
                    // rather than the MainActor-bound bridge.
                    let core = bridge.core
                    Task { await core.unsubscribeComments(subId: relaySubID) }
                    return
                }
                self.handleSubscribeResolved(callbackID: callbackID, relaySubID: relaySubID)
            } catch {
                Self.logger.warning("subscribe: core.subscribeComments failed — \(error, privacy: .public)")
                self?.tearDown(callbackID: callbackID)
            }
        }

        return Subscription(stream: stream, cancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(callbackID: callbackID)
            }
        })
    }

    /// Called by the kickoff Task once Rust hands back the relay-side
    /// sub id. If the caller already cancelled, immediately unsubscribe.
    private func handleSubscribeResolved(callbackID: UInt64, relaySubID: String) {
        guard let session = sessions[callbackID] else {
            // Session was torn down before the subscribe resolved.
            // Race-safe cleanup: unsubscribe the now-orphan relay sub.
            let core = PodcastrCoreBridge.shared.core
            Task { await core.unsubscribeComments(subId: relaySubID) }
            return
        }
        session.relaySubID = relaySubID
        if session.cancelled {
            tearDown(callbackID: callbackID)
        }
    }

    /// Caller-initiated cancel. Idempotent.
    private func cancel(callbackID: UInt64) {
        guard let session = sessions[callbackID] else { return }
        if session.relaySubID == nil {
            // The async subscribe hasn't returned yet — mark cancelled
            // and let `handleSubscribeResolved` complete the teardown
            // when the relay id arrives.
            session.cancelled = true
            return
        }
        tearDown(callbackID: callbackID)
    }

    /// Final teardown: unsubscribe from Rust, unregister the bridge
    /// handler, finish the stream, and drop the session entry.
    private func tearDown(callbackID: UInt64) {
        guard let session = sessions.removeValue(forKey: callbackID) else { return }
        if let handle = session.handle {
            PodcastrCoreBridge.shared.unregister(handle)
        }
        if let relaySubID = session.relaySubID {
            // Capture the (Sendable) `core` handle so the detached
            // Task body doesn't reach back through the MainActor-bound
            // bridge.
            let core = PodcastrCoreBridge.shared.core
            Task { await core.unsubscribeComments(subId: relaySubID) }
        }
        session.continuation.finish()
    }

    // MARK: - Delta routing

    /// Bridge delta handler. Matches comment deltas to their session by
    /// the carried `subscription_id` and forwards to the right stream.
    /// EOSE is intentionally swallowed — the original WebSocket
    /// implementation didn't surface it to callers and
    /// `EpisodeComment`/`Subscription` have no place to plumb it.
    private func handleDelta(_ delta: Delta) {
        guard let session = sessions[delta.subscriptionId] else { return }
        switch delta.change {
        case .commentReceived(let comment):
            ingest(comment: comment, into: session)
        case .subscriptionEose:
            // rust-cutover: original API doesn't surface EOSE.
            break
        default:
            // Other DataChangeType variants are not expected on a
            // comment subscription id; ignore defensively.
            break
        }
    }

    private func ingest(comment: CommentRecord, into session: Session) {
        guard !session.seenIDs.contains(comment.eventId) else { return }
        session.seenIDs.insert(comment.eventId)

        // `CommentRecord.anchorIdentifier` is the NIP-73 string; we
        // intentionally don't parse it back into a `CommentTarget` —
        // the session already knows its target (it was passed at
        // subscribe time), so we just reuse that.
        let comment = EpisodeComment(
            id: comment.eventId,
            target: session.target,
            authorPubkeyHex: comment.authorPubkey,
            content: comment.content,
            createdAt: Date(timeIntervalSince1970: TimeInterval(comment.createdAt))
        )
        session.continuation.yield(comment)
    }

    // MARK: - Publish

    /// Publish a NIP-22 top-level comment for `target`. The Rust core
    /// signs using the active session signer (local key or NIP-46
    /// bunker depending on user setup) and broadcasts to the relay
    /// pool. The returned `SignedNostrEvent` mirrors the wire event so
    /// the UI can optimistically append before the live subscription
    /// echoes it back.
    ///
    /// The `signer` parameter is retained for source compatibility
    /// with pre-cutover callers — it is unused. Signing happens in
    /// Rust via the active session signer.
    func publish(
        content: String,
        target: CommentTarget,
        signer: any NostrSigner  // rust-cutover: signing happens in Rust via the active session signer
    ) async throws -> SignedNostrEvent {
        _ = signer  // explicitly silence the "unused parameter" lint without changing the API
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PublishError.emptyContent }
        // Keep the relay-URL gate so callers without a configured
        // relay still get the same `noRelayConfigured` UX, even though
        // the URL itself is no longer consumed here — Rust owns the
        // relay pool now.
        guard relayURLProvider() != nil else { throw PublishError.noRelayConfigured }

        let anchor = Self.anchor(for: target)
        let signed: SignedEvent
        do {
            signed = try await PodcastrCoreBridge.shared.core.publishComment(
                content: trimmed,
                anchor: anchor
            )
        } catch {
            Self.logger.error("publish: core.publishComment failed — \(error, privacy: .public)")
            throw PublishError.relayRejected(error.localizedDescription)
        }

        return SignedNostrEvent(
            id: signed.id,
            pubkey: signed.pubkey,
            created_at: Int(signed.createdAt),
            kind: Int(signed.kind),
            tags: signed.tags,
            content: signed.content,
            sig: signed.sig
        )
    }

    // MARK: - Anchor mapping

    /// Bridge a Swift `CommentTarget` to the Rust `CommentAnchor`. The
    /// clip case forwards the UUID's lowercased string form to keep
    /// wire parity with the pre-cutover `nip73Identifier` formatting,
    /// where clip ids were lowercased.
    private static func anchor(for target: CommentTarget) -> CommentAnchor {
        switch target {
        case .episode(let guid):
            return .episode(guid: guid)
        case .clip(let id):
            return .clip(uuid: id.uuidString.lowercased())
        }
    }

    // MARK: - Errors

    /// Public surface kept identical to the pre-cutover service so
    /// callers don't need to change their `catch` branches. Some cases
    /// no longer fire after the cutover (e.g. `encodingFailed`,
    /// `relayAckTimeout`) but are retained for source compatibility.
    enum PublishError: LocalizedError {
        case emptyContent
        case noRelayConfigured
        case encodingFailed
        case relayRejected(String)
        case relayAckTimeout

        var errorDescription: String? {
            switch self {
            case .emptyContent:         "Comment is empty."
            case .noRelayConfigured:    "Set a Nostr relay URL in Settings before commenting."
            case .encodingFailed:       "Couldn't encode the comment for the relay."
            case .relayRejected(let m): "Relay rejected the comment: \(m)"
            case .relayAckTimeout:      "Relay didn't acknowledge in time."
            }
        }
    }
}
