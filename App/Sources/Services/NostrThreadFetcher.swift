import Foundation
import os.log

/// One-shot NIP-10 thread fetch: collects the root event plus every
/// kind:1 reply e-tagging it, then returns the lot sorted ascending by
/// `created_at`. Used by the peer-agent responder to assemble message
/// history before invoking the LLM.
///
/// After the Rust-core cutover the implementation no longer opens its
/// own WebSocket. It opens a streaming `subscribeThread` against the
/// shared `PodcastrCore` (which owns the relay pool) and returns the
/// accumulated events on the first `SubscriptionEose` — matching the
/// one-shot semantics callers expect.
///
/// A defensive hard timeout still applies: a relay that never sends
/// EOSE shouldn't be able to wedge the responder, so whatever was
/// collected up to the deadline is returned. The Rust pool internally
/// covers both filter legs (root id + replies) and fires EOSE once
/// stored events are flushed for the subscription.
@MainActor
final class NostrThreadFetcher {

    nonisolated private static let logger = Logger.app("NostrThreadFetcher")

    private enum Wire {
        /// Defensive fallback if EOSE never arrives. Matches the
        /// pre-cutover budget so caller timing assumptions hold.
        static let timeout: Duration = .seconds(4)
    }

    /// Wire-shape of an inbound kind:1 the responder needs to assemble
    /// a conversation. Surfaces only the fields the caller reads so the
    /// responder stays decoupled from the Rust `ThreadEventRecord`
    /// struct.
    struct Event: Sendable, Equatable {
        let id: String
        let pubkey: String
        let createdAt: Int
        let content: String
        let tags: [[String]]
    }

    /// Per-instance accumulator. Each `fetch` builds a fresh fetcher so
    /// concurrent fetches don't share state.
    private var collected: [String: Event] = [:]

    /// Fetch the root (by id) and all kind:1 replies that e-tag it.
    /// Results are de-duplicated by event id and sorted ascending by
    /// `created_at`. Returns an empty array on any hard failure — the
    /// caller is expected to proceed with whatever the inbound event
    /// itself carries.
    ///
    /// The `relayURL` parameter is retained for source compatibility
    /// with pre-cutover callers but is no longer consumed: Rust uses
    /// the shared client's relay pool.
    static func fetch(rootID: String, relayURL: URL) async -> [Event] {
        // rust-cutover: `relayURL` is unused — the Rust core owns the
        // relay pool. Parameter kept so existing callers compile.
        _ = relayURL
        return await NostrThreadFetcher().run(rootID: rootID)
    }

    private init() {}

    private func run(rootID: String) async -> [Event] {
        let bridge = PodcastrCoreBridge.shared

        // State shared between the bridge delta callback and the
        // awaiter. The continuation may be resumed by either the EOSE
        // delta or the timeout task, so we guard with a flag to avoid
        // double-resume.
        let state = WaitState()

        let handle = bridge.register { delta in
            // Bridge already hops to MainActor before invoking us.
            MainActor.assumeIsolated {
                self.handleDelta(delta, state: state)
            }
        }

        let relaySubID: String
        do {
            relaySubID = try await bridge.core.subscribeThread(
                rootEventId: rootID,
                callbackSubscriptionId: handle.callbackID
            )
        } catch {
            Self.logger.warning("fetch: core.subscribeThread failed — \(error, privacy: .public)")
            bridge.unregister(handle)
            return []
        }

        // Schedule the defensive timeout before we suspend on the
        // continuation. The timeout task runs on MainActor too, so all
        // mutations on `state` are single-threaded.
        Task { @MainActor in
            try? await Task.sleep(for: Wire.timeout)
            state.resumeIfNeeded(reason: .timeout)
        }

        // Wait for the first EOSE (preferred) or the defensive
        // timeout. `install` handles the "signal latched before
        // continuation was installed" case — EOSE can fire while we
        // were awaiting the Rust subscribe above.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.install(continuation)
        }

        // Tear down: unsubscribe from Rust, unregister the bridge
        // handler, then return the accumulator sorted ascending.
        await bridge.core.unsubscribeThread(subId: relaySubID)
        bridge.unregister(handle)

        return collected.values.sorted { $0.createdAt < $1.createdAt }
    }

    /// Tracks resume state for the EOSE/timeout race. Both paths call
    /// `resumeIfNeeded`; only the first one with both the continuation
    /// installed AND a settle signal latched wins. MainActor-isolated
    /// so producers (delta handler, timeout task) and the awaiter
    /// share one mutation context.
    ///
    /// The "settle before install" case is real: between
    /// `bridge.register(...)` and `withCheckedContinuation { ... }`,
    /// we await the Rust subscribe call. EOSE can arrive during that
    /// suspension. We latch `eoseSeen`/`timeoutFired` independently of
    /// `continuation`, and `install` (called inside the continuation
    /// body) resumes immediately if a signal already latched.
    @MainActor
    private final class WaitState {
        enum Reason { case eose, timeout }
        private var continuation: CheckedContinuation<Void, Never>?
        private var resumed = false
        private var eoseSeen = false
        private var timeoutFired = false

        func install(_ continuation: CheckedContinuation<Void, Never>) {
            if eoseSeen || timeoutFired {
                // A signal already latched while we were awaiting the
                // Rust subscribe. Resume now — don't bother saving.
                guard !resumed else { return }
                resumed = true
                continuation.resume()
                return
            }
            self.continuation = continuation
        }

        func resumeIfNeeded(reason: Reason) {
            switch reason {
            case .eose:    eoseSeen = true
            case .timeout: timeoutFired = true
            }
            guard !resumed, let c = continuation else { return }
            resumed = true
            continuation = nil
            c.resume()
        }
    }

    private func handleDelta(_ delta: Delta, state: WaitState) {
        switch delta.change {
        case .threadEventReceived(let event):
            ingest(event: event)
        case .subscriptionEose:
            // `resumeIfNeeded` latches `eoseSeen` itself; no need to
            // set it separately here.
            state.resumeIfNeeded(reason: .eose)
        default:
            // Other DataChangeType variants are not expected on a
            // thread subscription id; ignore defensively.
            break
        }
    }

    private func ingest(event: ThreadEventRecord) {
        // Dedup by event id — the Rust pool may surface the same event
        // across both filter legs (the root id filter + the e-tag
        // reply filter) for the root itself.
        collected[event.eventId] = Event(
            id: event.eventId,
            pubkey: event.pubkey,
            createdAt: Int(event.createdAt),
            content: event.content,
            tags: event.tags
        )
    }
}
