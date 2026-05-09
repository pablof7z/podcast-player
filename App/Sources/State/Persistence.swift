import Foundation
import os.log

/// Persists AppState as a JSON blob in the shared App Group UserDefaults.
/// The App Group allows widgets and extensions to read the same state.
///
/// SETUP: Replace the suite name with your actual App Group identifier.
/// It must match APP_GROUP_IDENTIFIER in Project.swift and your entitlements.
enum Persistence {
    private static let logger = Logger.app("Persistence")
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

    /// The App Group suite name.
    ///
    /// Reads `AppGroupIdentifier` from the main bundle's Info.plist so the
    /// value comes from the Tuist `APP_GROUP_IDENTIFIER` build setting and
    /// stays in sync with the entitlements automatically.
    ///
    /// For extension targets (e.g. WidgetKit) whose `Bundle.main` is the
    /// extension bundle, add `AppGroupIdentifier` to their Info.plist with
    /// the same `$(APP_GROUP_IDENTIFIER)` substitution.
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.pablofernandez.apptemplate"   // compile-time fallback
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static let stateKey = "apptemplate.state.v1"

    /// Encodes `state` to JSON and writes it to the shared App Group UserDefaults.
    ///
    /// This method is intentionally non-throwing: encode failures are logged
    /// via `os.Logger` and the existing persisted data is left untouched.
    static func save(_ state: AppState) {
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            logger.error("Persistence.save: encode failed: \(error, privacy: .public)")
            return
        }
        defaults.set(data, forKey: stateKey)
    }

    /// Loads and decodes `AppState` from the shared App Group UserDefaults.
    ///
    /// - Returns: The previously saved `AppState`, or a fresh `AppState()` when
    ///   no persisted data exists yet.
    /// - Throws: Any `DecodingError` produced by `JSONDecoder` when the stored
    ///   data cannot be decoded. Callers should handle this by falling back to a
    ///   default state.
    static func load() throws -> AppState {
        guard let data = defaults.data(forKey: stateKey) else { return AppState() }
        return try decoder.decode(AppState.self, from: data)
    }
}
