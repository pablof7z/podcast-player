import Foundation
import os.log

/// Persists `AppState` as a JSON blob in a file inside the shared App Group
/// container.
///
/// **Why a file, not `UserDefaults`.** A previous iteration wrote the blob to
/// `UserDefaults(suiteName: <App Group>)`. Once a user subscribed to a real
/// podcast, `state.episodes` ballooned the encoded blob past a few MB and
/// `cfprefsd` silently dropped the value on the next read — `data(forKey:)`
/// returned the previous (smaller) committed version, so anything written
/// after the size crossover was lost. The symptom was: complete onboarding,
/// kill the app, relaunch, and onboarding shows again because the
/// `hasCompletedOnboarding=true` save (which by then sat alongside the
/// episode list) never came back through the prefs daemon. `UserDefaults` is
/// fundamentally not designed for blobs of this size; the App Group
/// container's filesystem is.
///
/// **Atomic writes.** Saves go through `Data.write(to:options: .atomic)` so a
/// crash mid-write leaves the previous good blob in place rather than a
/// half-written file that would fail to decode and silently reset the user
/// to a fresh `AppState`.
///
/// **Production vs. tests.** Construct via `Persistence.shared` for production
/// (writes to `<app-group>/Library/Application Support/podcastr-state.v1.json`).
/// Tests construct an isolated instance against a unique temp file URL so
/// fixtures never leak into the real app's storage — the bug where launching
/// the app after running the test target showed phantom "Test Show" /
/// "Episode e1" was caused by both contexts writing to the same App Group key.
struct Persistence: Sendable {

    /// Shared, production-default instance writing to the App Group container.
    static let shared = Persistence(fileURL: Persistence.appGroupStateFileURL)

    /// File this instance reads from / writes to.
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - State persistence

    /// Encodes `state` to JSON and writes it atomically to `fileURL`.
    ///
    /// Intentionally non-throwing: encode/write failures are logged via
    /// `os.Logger` and the existing persisted file is left untouched (the
    /// `.atomic` write would refuse to clobber on failure anyway) so a
    /// transient encoder bug can't drop the user's library.
    func save(_ state: AppState) {
        let data: Data
        do {
            data = try Self.encoder.encode(state)
        } catch {
            Self.logger.error("Persistence.save: encode failed: \(error, privacy: .public)")
            return
        }
        do {
            try ensureParentDirectoryExists()
            try data.write(to: fileURL, options: [.atomic])
            Self.logger.info("Persistence.save: bytes=\(data.count, privacy: .public)")
        } catch {
            Self.logger.error("Persistence.save: write failed at \(self.fileURL.path, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Loads and decodes `AppState` from `fileURL`.
    ///
    /// - Returns: The previously saved `AppState`, or a fresh `AppState()`
    ///   when no persisted file exists yet (including the one-shot path
    ///   where this is the very first launch under the file-based backend
    ///   and there's also no legacy `UserDefaults` blob to migrate).
    /// - Throws: Any `DecodingError` produced by `JSONDecoder` when the
    ///   stored data cannot be decoded. Callers fall back to a default state.
    func load() throws -> AppState {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(AppState.self, from: data)
        }
        // One-shot migration: an earlier build wrote `AppState` to App Group
        // `UserDefaults` under `legacyStateKey`. If a user is launching the
        // first build that uses the file backend, recover whatever the prefs
        // daemon was still serving (which is small enough to round-trip) so
        // their settings + small libraries survive the upgrade. After a
        // successful migration we wipe the legacy key so we never read it
        // again. Migration only runs for `Persistence.shared`; isolated
        // test instances point at temp files and have no legacy data.
        if fileURL == Self.appGroupStateFileURL,
           let legacyData = Self.appGroupDefaults.data(forKey: Self.legacyStateKey) {
            let migrated = try Self.decoder.decode(AppState.self, from: legacyData)
            try? ensureParentDirectoryExists()
            try? legacyData.write(to: fileURL, options: [.atomic])
            Self.appGroupDefaults.removeObject(forKey: Self.legacyStateKey)
            Self.logger.info("Persistence.load: migrated \(legacyData.count, privacy: .public) bytes from legacy UserDefaults key")
            return migrated
        }
        return AppState()
    }

    /// Wipes the persisted `AppState` file. Intended for the "Erase all
    /// data" code path and for test cleanup. Idempotent — missing files
    /// are not an error.
    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
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

    /// `UserDefaults` instance for the App Group suite. Retained only for
    /// the legacy-blob migration in `load()`; production reads/writes go
    /// through the file backend.
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// Absolute file URL for the production state blob inside the App Group
    /// container. Falls back to the user's caches directory when the App
    /// Group entitlement is missing (e.g. a stripped-down developer build) —
    /// parity with the old `appGroupDefaults ?? .standard` fallback.
    static var appGroupStateFileURL: URL {
        let manager = FileManager.default
        let base: URL
        if let groupContainer = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            base = groupContainer.appendingPathComponent("Library/Application Support", isDirectory: true)
        } else {
            // Fallback: app-local caches. The widget can't reach this, but
            // neither can it reach UserDefaults.standard — same trade-off
            // as the previous fallback.
            let caches = (try? manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            base = caches
        }
        return base.appendingPathComponent("podcastr-state.v1.json", isDirectory: false)
    }

    // MARK: - Static helpers

    private static let logger = Logger.app("Persistence")
    /// Prior-art `UserDefaults` key the file backend migrates from on first
    /// run. Kept as a string constant (not exposed) so the migration path
    /// stays self-documenting.
    private static let legacyStateKey = "podcastr.state.v1"

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

    /// Creates the parent directory tree for `fileURL` if it doesn't already
    /// exist. App Group containers ship with `Library/` but not necessarily
    /// `Library/Application Support/`; `Data.write` would fail with ENOENT
    /// if we didn't precreate the path.
    private func ensureParentDirectoryExists() throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
