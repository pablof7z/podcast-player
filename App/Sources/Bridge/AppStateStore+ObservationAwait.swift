import Foundation

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

extension AppStateStore {

    /// Await a derived value from the store, recomputed reactively whenever any
    /// `@Observable` property read inside `body` changes.
    ///
    /// `body` is evaluated immediately; if it already returns a non-`nil`
    /// value, that value is returned without suspending. Otherwise the awaiter
    /// arms `withObservationTracking` on exactly the properties `body` touched
    /// and suspends until one of them mutates, then re-evaluates — looping
    /// until `body` yields a value or `timeout` elapses.
    ///
    /// Correctness notes:
    /// - Runs on the `@MainActor` (the store's isolation), the same actor on
    ///   which `applyKernelState` performs its writes. The predicate is
    ///   evaluated, and the observation armed, with no `await` in between — so
    ///   no projection write can interleave between the check and the arm.
    ///   There is no check-then-arm gap where a mutation could be missed.
    /// - The predicate is read once *outside* tracking to short-circuit when it
    ///   is already satisfied (no suspension), then — only when unsatisfied —
    ///   re-read *inside* `withObservationTracking` to arm on exactly those
    ///   reads. `onChange` fires once on the next mutation, then disarms; the
    ///   loop re-arms on each iteration.
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
            // Arm observation on the same reads, then suspend until one of them
            // mutates. No `await` runs between the check above and this arm, so
            // a projection write cannot slip through unobserved.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = body()
                } onChange: {
                    continuation.resume()
                }
            }
        }
        return nil
    }
}
