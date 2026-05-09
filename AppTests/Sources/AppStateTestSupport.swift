import Foundation
@testable import Podcastr

// MARK: - AppStateTestSupport
//
// Test-only helpers for spinning up an `AppStateStore` whose persistence is
// fully isolated from the production App Group suite.
//
// The bug this guards against: tests used to construct `AppStateStore()` with
// no arguments, which fell through to the shared App Group `UserDefaults`
// (`group.com.podcastr.app`). Anything a test wrote — `Test Show`, `Episode
// e1`, etc. — survived the test run and showed up the next time the actual
// app launched on the simulator.
//
// `makeIsolatedStore()` builds a `Persistence` bound to a brand-new
// in-memory `UserDefaults` suite (the suite name is uniquified per call),
// so:
//
//   - Each test instance starts from a clean slate (no cross-test bleed).
//   - Nothing the tests write touches the real App Group key.
//   - The temporary suite is wiped via `removePersistentDomain(forName:)`
//     in `tearDown` to be doubly safe even if an OS quirk persisted the
//     ephemeral suite.
enum AppStateTestSupport {

    /// Builds an `AppStateStore` backed by a unique `UserDefaults` suite so
    /// the test never touches the production App Group storage.
    @MainActor
    static func makeIsolatedStore(
        suiteName: String = "podcastr.tests.\(UUID().uuidString)"
    ) -> (store: AppStateStore, suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        // Belt-and-suspenders: clear anything a previous (crashed) test
        // run may have left in this exact suite.
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = Persistence(suite: defaults)
        let store = AppStateStore(persistence: persistence)
        return (store, suiteName)
    }

    /// Erases a temporary suite created by `makeIsolatedStore`. Safe to
    /// call from `tearDown`; idempotent if the suite is already gone.
    static func disposeIsolatedSuite(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// Wipes the production App Group state key. Use only as a one-shot
    /// repair from a development build that previously corrupted the
    /// shared suite (e.g. the test-leak bug being fixed in this branch).
    static func resetPersistedState() {
        Persistence.shared.reset()
    }
}
