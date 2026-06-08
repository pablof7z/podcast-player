import Foundation
import os

// MARK: - Reactive state awaiters
//
// Kernel mutations (`kernelSubscribe`, `kernelSummarizeEpisode`,
// `kernelEnsurePodcast`) are fire-and-forget: Rust enqueues the action and the
// result lands asynchronously on the next snapshot projection, when
// `applyKernelState` writes `self.state` / `self.episodes`. Callers that need
// to await that result used to spin a `Task.sleep(300ms)` poll loop, which
// added up to 300ms of latency on every success and burned wakeups while
// waiting.
//
// `awaitState` replaces those polls with `withObservationTracking`: it reads
// the relevant `@Observable` properties through `body`, and — because
// `AppStateStore` is `@Observable` — the kernel projection's write to `state`
// or `episodes` resumes the awaiter on the very next runloop turn, with no
// fixed timer. The first satisfying snapshot wins; nothing wakes in between.
// A `timeout` racer (see below) guarantees the awaiter still returns `nil`
// when the awaited state never arrives (e.g. Ollama offline, feed unreachable).

/// A continuation that may be resumed from multiple racing sources (an
/// `Observation` `onChange` and a timeout) but must resume its underlying
/// continuation exactly once. The lock makes the guard safe across the
/// arbitrary executors those sources run on — the `@MainActor`-bound caller,
/// the `onChange` callback, and the timeout `Task` may all fire concurrently.
///
/// `fire()` may legitimately arrive *before* `arm()` (a near-zero timeout can
/// schedule before the continuation is stored), so a pending fire is latched
/// and replayed when `arm()` runs — otherwise that race would leak a never-
/// resumed continuation and hang the awaiter.
private final class OneShotResume: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var firedBeforeArm = false
        var resumed = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Store the continuation to resume later. Called once, synchronously
    /// inside `withCheckedContinuation`. If a racer already fired, resume now.
    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow: Bool = state.withLock { s in
            if s.firedBeforeArm {
                s.resumed = true
                return true
            }
            s.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    /// Resume the continuation if it has not already been resumed. The first
    /// caller wins; later calls (and a fire that beats `arm`) are no-ops beyond
    /// latching the pending fire.
    func fire() {
        let continuation: CheckedContinuation<Void, Never>? = state.withLock { s in
            guard !s.resumed else { return nil }
            if let c = s.continuation {
                s.continuation = nil
                s.resumed = true
                return c
            }
            // Fired before `arm` stored a continuation — latch it.
            s.firedBeforeArm = true
            return nil
        }
        continuation?.resume()
    }
}

extension AppStateStore {

    /// Await a derived value from the store, recomputed reactively whenever any
    /// `@Observable` property read inside `body` changes.
    ///
    /// `body` is evaluated immediately; if it already returns a non-`nil`
    /// value, that value is returned without suspending. Otherwise the awaiter
    /// arms `withObservationTracking` on exactly the properties `body` touched
    /// and suspends until one of them mutates (or the timeout fires), then
    /// re-evaluates — looping until `body` yields a value or `timeout` elapses.
    ///
    /// Correctness notes:
    /// - Runs on the `@MainActor` (the store's isolation), the same actor on
    ///   which `applyKernelState` performs its writes. The predicate is
    ///   evaluated, and the observation armed, with no `await` in between — so
    ///   no projection write can interleave between the check and the arm.
    ///   There is no check-then-arm gap where a mutation could be missed.
    /// - Each suspension races the `Observation` change against an absolute
    ///   `timeout` deadline. Without that racer the timeout path would hang
    ///   forever: when the awaited state never arrives, `onChange` never fires,
    ///   so the loop's deadline check would never be reached. The timeout child
    ///   guarantees the suspension always resumes, after which the `while`
    ///   condition re-evaluates the deadline and exits with `nil`.
    /// - The shared continuation is resumed exactly once (`OneShotResume`),
    ///   safely across the observation callback, the timeout task, and task
    ///   cancellation — so a cancelled awaiter (e.g. the timeout tearing down
    ///   the observation child) never leaks a parked continuation.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait before returning `nil`.
    ///   - body: Produces the awaited value (or `nil` if not ready yet) from
    ///     observable store state.
    /// - Returns: The first non-`nil` value `body` produces, or `nil` on timeout.
    func awaitState<Value>(
        timeout: Duration,
        body: @escaping () -> Value?
    ) async -> Value? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            // Fast path: already satisfied — return without suspending.
            if let result = body() { return result }

            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { break }

            // Suspend until either an observed property changes or `remaining`
            // elapses, then loop to re-evaluate `body()` and the deadline.
            //
            // A single continuation is resumed by whichever fires first:
            //   - the `Observation` `onChange` (an awaited property mutated), or
            //   - a detached timeout `Task` after `remaining`.
            // `OneShotResume` guarantees exactly-one resume across those racers.
            // The observation arming stays directly on the `@MainActor` caller
            // (no child task captures the non-`Sendable` `body`), so `body` is
            // only ever read on the store's own actor.
            let resumer = OneShotResume()
            let timeoutTask = Task {
                try? await Task.sleep(for: remaining)
                resumer.fire()
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                resumer.arm(continuation)
                withObservationTracking {
                    _ = body()
                } onChange: {
                    resumer.fire()
                }
            }
            // Whoever lost the race is now redundant: cancel the timer so it
            // doesn't linger, and drop any pending fire (already a no-op).
            timeoutTask.cancel()
        }
        return nil
    }
}
