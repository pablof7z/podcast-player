import Foundation

/// Process-wide bridge to the Rust `PodcastrCore` FFI.
///
/// One `PodcastrCore` instance lives for the lifetime of the app. The bridge
/// owns it, installs itself as the single `EventCallback`, and fans every
/// incoming `Delta` out to per-subscription Swift handlers keyed by the
/// `callback_subscription_id` the consumer used when opening the subscription.
///
/// Why this shape:
/// * The Rust core can only carry one `EventCallback`. Multiple Swift services
///   need to receive deltas, so the bridge multiplexes.
/// * `subscription_id == 0` is reserved for app-scoped events (signer state,
///   relay status) — broadcast to a separate sink.
/// * Each service generates a unique id via `nextSubscriptionID()` BEFORE
///   opening a subscription, registers its handler, then calls the Rust
///   `subscribe…(callbackSubscriptionId:)` method with that same id.
///
/// Lifecycle on each handle: the caller MUST `unregister(handle)` (and also
/// invoke the corresponding `unsubscribe…` on the Rust side) when its view /
/// store deallocates — otherwise the subscription leaks both in the registry
/// and on the relay pool. The returned `SubscriptionHandle` is a thin id
/// wrapper that does NOT auto-unregister on dealloc — Swift owners must do
/// teardown explicitly to keep the lifecycle predictable across actor hops.
@MainActor
final class PodcastrCoreBridge: NSObject {

    // MARK: - Singleton

    static let shared = PodcastrCoreBridge()

    // MARK: - Rust handle

    /// The single `PodcastrCore` instance. Every Nostr operation routes
    /// through this — never call FFI methods on a different `PodcastrCore`
    /// constructed elsewhere.
    let core: PodcastrCore

    // MARK: - Delta multiplexing

    /// Handler registered for a single open subscription.
    struct Subscription: Sendable {
        let id: UInt64
        let onDelta: @Sendable (Delta) -> Void
    }

    /// Subscription handle returned to callers. They pass this back to
    /// `unregister` (Swift side) and to the corresponding Rust
    /// `unsubscribe…(subId:)` method.
    struct SubscriptionHandle: Sendable {
        let callbackID: UInt64
    }

    /// App-scoped sink for `subscription_id == 0` deltas (signer state, relay
    /// status, etc). Multiple observers can attach; each receives every
    /// app-scoped delta.
    struct AppObserver: Sendable {
        let token: UInt64
        let onDelta: @Sendable (Delta) -> Void
    }

    // Per-subscription routing. Accessed only from MainActor.
    private var handlers: [UInt64: Subscription] = [:]
    private var appObservers: [UInt64: AppObserver] = [:]
    private var nextCallbackID: UInt64 = 1
    private var nextObserverToken: UInt64 = 1

    // MARK: - Init

    private override init() {
        self.core = PodcastrCore()
        super.init()
        // Install ourselves as the single callback sink. The Rust core fans
        // every Delta back through `onDataChanged`.
        let sink = DeltaSink { [weak self] delta in
            // Rust invokes us on a background thread (the tokio pump). Hop to
            // MainActor so handler state and subsequent UI work stay isolated.
            Task { @MainActor [weak self] in
                self?.deliver(delta: delta)
            }
        }
        core.setEventCallback(callback: sink)
    }

    // MARK: - Registration API for Swift services

    /// Allocate a fresh callback id and install a delta handler under it.
    /// The handler runs on the MainActor. Returns the handle the caller
    /// passes to `unregister` and to the Rust `unsubscribe…` method.
    func register(onDelta: @escaping @Sendable (Delta) -> Void) -> SubscriptionHandle {
        let id = nextCallbackID
        nextCallbackID += 1
        handlers[id] = Subscription(id: id, onDelta: onDelta)
        return SubscriptionHandle(callbackID: id)
    }

    /// Remove a previously registered handler. Idempotent.
    func unregister(_ handle: SubscriptionHandle) {
        handlers.removeValue(forKey: handle.callbackID)
    }

    /// Attach an observer for app-scoped (`subscription_id == 0`) deltas
    /// such as signer state and relay status. Returns an opaque token used
    /// to detach later via `removeAppObserver`.
    func addAppObserver(onDelta: @escaping @Sendable (Delta) -> Void) -> UInt64 {
        let token = nextObserverToken
        nextObserverToken += 1
        appObservers[token] = AppObserver(token: token, onDelta: onDelta)
        return token
    }

    /// Detach an app-scoped observer. Idempotent.
    func removeAppObserver(_ token: UInt64) {
        appObservers.removeValue(forKey: token)
    }

    // MARK: - Dispatch

    private func deliver(delta: Delta) {
        if delta.subscriptionId == 0 {
            for observer in appObservers.values {
                observer.onDelta(delta)
            }
            return
        }
        if let handler = handlers[delta.subscriptionId] {
            handler.onDelta(delta)
        }
        // Unknown id: silently drop — caller may have unregistered between
        // the Rust pump dispatching the event and the MainActor hop.
    }
}

// MARK: - EventCallback adapter

/// `EventCallback` is the UniFFI-generated protocol; the Rust core invokes
/// `onDataChanged(delta:)` from its background pump thread. We wrap a
/// closure so the bridge can stay an actor-bound object while still meeting
/// the `Sendable` protocol requirement.
private final class DeltaSink: EventCallback, @unchecked Sendable {
    private let handler: @Sendable (Delta) -> Void
    init(_ handler: @escaping @Sendable (Delta) -> Void) {
        self.handler = handler
    }
    func onDataChanged(delta: Delta) {
        handler(delta)
    }
}
