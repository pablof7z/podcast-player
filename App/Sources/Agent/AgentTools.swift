import Foundation
import os.log

/// Defines the tools the agent can call and dispatches them to AppStateStore.
/// Add new tools by:
///   1. Adding a schema entry in `AgentToolSchema.swift`
///   2. Adding a case to `dispatch` below
///   3. Implementing the handler in the appropriate `AgentTools+*.swift` extension
enum AgentTools {

    static let logger = Logger.app("AgentTools")

    // MARK: - Constants

    /// Maximum number of characters used when truncating text in activity summaries.
    static let summaryTruncationLength = 40
    /// Placeholder title used when a matching item cannot be found in the store.
    static let unknownItemTitle = "item"

    // MARK: - Tool names

    /// Canonical string identifiers for every tool the agent can call.
    ///
    /// Reference these constants instead of raw string literals so that any
    /// rename is caught by the compiler in both `AgentToolSchema.schema` and `dispatch`.
    enum Names {
        static let createItem       = "create_item"
        static let setItemPriority  = "set_item_priority"
        static let updateItem       = "update_item"
        static let markItemDone     = "mark_item_done"
        static let deleteItem       = "delete_item"
        static let createNote       = "create_note"
        static let recordMemory     = "record_memory"
        static let setReminder      = "set_reminder"
        static let clearReminder    = "clear_reminder"
        static let findItems        = "find_items"
        static let setDueDate       = "set_due_date"
        static let clearDueDate     = "clear_due_date"
        static let addTag               = "add_tag"
        static let removeTag            = "remove_tag"
        static let setItemColorTag      = "set_item_color_tag"
        static let setEstimatedMinutes  = "set_estimated_minutes"
        static let clearEstimatedMinutes = "clear_estimated_minutes"
        static let pinItem              = "pin_item"
        static let unpinItem            = "unpin_item"
        static let renameTag            = "rename_tag"
    }

    // MARK: - Search constants

    /// Maximum number of items returned by `find_items`, regardless of what the model requests.
    static let findItemsMaxLimit = 20
    /// Default result limit when the model omits `limit`.
    static let findItemsDefaultLimit = 10

    // MARK: - Cached formatters

    // ISO8601DateFormatter is thread-safe for reads after setup — nonisolated(unsafe) suppresses
    // the Swift 6 Sendable warning without wrapping in a lock.
    nonisolated(unsafe) static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let iso8601Basic = ISO8601DateFormatter()

    // MARK: - Dispatcher

    @MainActor
    static func dispatch(name: String, argsJSON: String, store: AppStateStore, batchID: UUID) async -> String {
        let args: [String: Any]
        do {
            args = try JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any] ?? [:]
        } catch {
            logger.error("AgentTools: failed to parse argsJSON for tool '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            args = [:]
        }

        switch name {
        case Names.createItem, Names.setItemPriority, Names.updateItem, Names.markItemDone, Names.deleteItem,
             Names.addTag, Names.removeTag, Names.setItemColorTag,
             Names.setEstimatedMinutes, Names.clearEstimatedMinutes,
             Names.pinItem, Names.unpinItem, Names.renameTag:
            return await dispatchItems(name: name, args: args, store: store, batchID: batchID)

        case Names.createNote, Names.recordMemory:
            return dispatchNotesMemory(name: name, args: args, store: store, batchID: batchID)

        case Names.setReminder, Names.clearReminder:
            return await dispatchReminders(name: name, args: args, store: store, batchID: batchID)

        case Names.setDueDate, Names.clearDueDate:
            return dispatchDueDates(name: name, args: args, store: store, batchID: batchID)

        case Names.findItems:
            return dispatchSearch(args: args, store: store)

        default:
            return toolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Helpers

    /// Builds a JSON success response, merging `payload` into `{"success": true}`.
    static func toolSuccess(_ payload: [String: Any] = [:]) -> String {
        var result: [String: Any] = ["success": true]
        result.merge(payload) { _, new in new }
        do {
            return try String(data: JSONSerialization.data(withJSONObject: result), encoding: .utf8) ?? "{\"success\":true}"
        } catch {
            logger.error("AgentTools: failed to serialize success payload: \(error.localizedDescription, privacy: .public)")
            return "{\"success\":true}"
        }
    }

    /// Builds a JSON error response with the given message.
    static func toolError(_ message: String) -> String {
        let payload: [String: Any] = ["error": message]
        do {
            return try String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? "{\"error\":\"unknown\"}"
        } catch {
            logger.error("AgentTools: failed to serialize error payload '\(message, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return "{\"error\":\"unknown\"}"
        }
    }

    /// Returns `s` truncated to `summaryTruncationLength` characters with a
    /// trailing ellipsis when the string was shortened, or the original string
    /// when it fits within the limit.
    static func truncated(_ s: String) -> String {
        s.count > summaryTruncationLength
            ? "\(s.prefix(summaryTruncationLength))…"
            : s
    }
}
