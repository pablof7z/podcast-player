import Foundation
import os.log

extension Logger {
    /// Creates a `Logger` scoped to this app's bundle identifier, with the given category.
    ///
    /// Use this instead of repeating `Logger(subsystem: Bundle.main.bundleIdentifier ?? "Podcastr", category: …)`
    /// at every call site.
    ///
    /// ```swift
    /// private let logger = Logger.app("MyView")
    /// private static let logger = Logger.app("MyService")
    /// ```
    static func app(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Podcastr", category: category)
    }
}
