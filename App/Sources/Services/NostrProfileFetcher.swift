import Foundation
import os.log

/// One-shot kind:0 (`metadata`) fetcher. Delegates relay I/O to the Rust
/// core via `PodcastrCoreBridge`. Subscribes for profile records for the
/// given pubkeys, writes each one into `AppStateStore.state.nostrProfileCache`
/// as deltas arrive, and tears down when either EOSE arrives or a 4s
/// timeout fires — whichever comes first.
///
/// Designed to be cheap to call: the subscription closes as soon as EOSE
/// arrives, or after a hard timeout. Concurrent calls are safe — each one
/// owns its own callback id and Rust subscription id.
@MainActor
final class NostrProfileFetcher {

    nonisolated private static let logger = Logger.app("NostrProfileFetcher")

    private enum Wire {
        static let timeout: Duration = .seconds(4)
    }

    private let store: AppStateStore

    init(store: AppStateStore) {
        self.store = store
    }

    /// Requests kind:0 events for `pubkeys` and caches whatever comes back
    /// before EOSE or timeout. Returns when the subscription closes.
    func fetchProfiles(for pubkeys: [String]) async {
        guard !pubkeys.isEmpty else { return }

        let bridge = PodcastrCoreBridge.shared

        // Single-shot signal: resumed either by EOSE delta or the timeout.
        // Wrapped in a class so the `@Sendable` delta handler can mutate
        // it under the main actor without capture-by-value issues.
        let signal = OneShotSignal()

        let handle = bridge.register { [weak self] delta in
            // Bridge already hops to MainActor before invoking us.
            MainActor.assumeIsolated {
                guard let self else { return }
                switch delta.change {
                case .profileUpdated(let pubkey, let profile):
                    let metadata = NostrProfileMetadata(
                        pubkey: pubkey,
                        name: profile.name,
                        displayName: profile.displayName,
                        about: profile.about,
                        picture: profile.picture,
                        nip05: profile.nip05,
                        fetchedFromCreatedAt: Int(profile.createdAt)
                    )
                    self.store.setNostrProfile(metadata)
                case .subscriptionEose:
                    signal.fire()
                default:
                    break
                }
            }
        }

        let subID: String
        do {
            subID = try await bridge.core.subscribeProfiles(
                pubkeys: pubkeys,
                callbackSubscriptionId: handle.callbackID
            )
        } catch {
            Self.logger.warning("fetchProfiles: subscribe failed — \(error, privacy: .public)")
            bridge.unregister(handle)
            return
        }

        // Race EOSE vs the 4s timeout. First one to fire wins; the other
        // is cancelled. This is a one-shot bounded wait, not a poll loop.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await signal.wait()
            }
            group.addTask {
                try? await Task.sleep(for: Wire.timeout)
            }
            await group.next()
            group.cancelAll()
        }

        await bridge.core.unsubscribeProfiles(subId: subID)
        bridge.unregister(handle)
    }
}

// MARK: - One-shot signal

/// Internal helper: a single-resume continuation guarded against double-fire.
/// Used to let the delta handler "ping" the awaiter exactly once when
/// `.subscriptionEose` arrives. Living on the MainActor keeps mutation safe
/// because both `fire()` and `wait()` are called there.
@MainActor
private final class OneShotSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func fire() {
        guard !fired else { return }
        fired = true
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
    }

    func wait() async {
        if fired { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if fired || Task.isCancelled {
                    cont.resume()
                } else {
                    self.continuation = cont
                }
            }
        } onCancel: {
            // Cancellation arrives on an unspecified executor; hop back to the
            // MainActor to resume the (MainActor-isolated) continuation safely.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let cont = self.continuation {
                    self.continuation = nil
                    cont.resume()
                }
            }
        }
    }
}
