import Foundation
import os.log

/// Persists `AppState` as a JSON blob in a `UserDefaults` suite.
///
/// In production we point at the shared App Group suite so widgets and
/// extensions can read the same blob. Tests construct an isolated instance
/// against an in-memory suite (`UserDefaults(suiteName: "test-…")`) so test
/// runs never leak fixtures into the production app's storage — the bug
/// where launching the app after running the test target showed a phantom
/// "Test Show" / "Episode e1" was caused by both contexts writing to the
/// same App Group key.
///
/// Construct via `Persistence.shared` for production code, or call the
/// `init(suite:)` initializer from tests with a unique suite name.
///
/// `@unchecked Sendable` because `UserDefaults` itself is documented as
/// thread-safe but is not yet annotated `Sendable` by the SDK. We only
/// store the reference and forward to it.
struct Persistence: @unchecked Sendable {

    /// Shared, production-default instance writing to the App Group suite
    /// declared in `Project.swift` (mirrored to `Info.plist` as
    /// `AppGroupIdentifier`).
    static let shared = Persistence(suite: Persistence.appGroupDefaults)

    /// `UserDefaults` suite this instance reads from / writes to.
    let defaults: UserDefaults

    init(suite: UserDefaults) {
        self.defaults = suite
    }

    // MARK: - State persistence

    /// Encodes `state` to JSON and writes it to the configured suite.
    ///
    /// Intentionally non-throwing: encode failures are logged via
    /// `os.Logger` and the existing persisted data is left untouched so a
    /// transient encoder bug can't drop the user's library.
    func save(_ state: AppState) {
        let data: Data
        do {
            data = try Self.encoder.encode(state)
        } catch {
            Self.logger.error("Persistence.save: encode failed: \(error, privacy: .public)")
            return
        }
        defaults.set(data, forKey: Self.stateKey)
    }

    /// Loads and decodes `AppState` from the configured suite.
    ///
    /// - Returns: The previously saved `AppState`, or a fresh `AppState()`
    ///   when no persisted data exists yet.
    /// - Throws: Any `DecodingError` produced by `JSONDecoder` when stored
    ///   data cannot be decoded. Callers fall back to a default state.
    func load() throws -> AppState {
        guard let data = defaults.data(forKey: Self.stateKey) else { return AppState() }
        return try Self.decoder.decode(AppState.self, from: data)
    }

    /// Wipes the persisted `AppState` from the configured suite. Intended
    /// for the "Erase all data" code path and for test cleanup.
    func reset() {
        defaults.removeObject(forKey: Self.stateKey)
    }

    // MARK: - Suite resolution

    /// The App Group suite name.
    ///
    /// Reads `AppGroupIdentifier` from the main bundle's `Info.plist` so
    /// the value comes from the Tuist `APP_GROUP_IDENTIFIER` build setting
    /// and stays in sync with the entitlements automatically.
    ///
    /// For extension targets (e.g. WidgetKit) whose `Bundle.main` is the
    /// extension bundle, add `AppGroupIdentifier` to their `Info.plist`
    /// with the same `$(APP_GROUP_IDENTIFIER)` substitution.
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.podcastr.app"   // compile-time fallback
    }

    /// `UserDefaults` instance backing `Persistence.shared`. Falls back to
    /// `.standard` when the App Group entitlement is missing (e.g. running
    /// under a stripped-down developer build).
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    // MARK: - Static helpers

    private static let logger = Logger.app("Persistence")
    private static let stateKey = "podcastr.state.v1"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
