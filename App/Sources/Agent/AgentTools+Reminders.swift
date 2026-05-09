import Foundation

// MARK: - Reminder tool handlers

extension AgentTools {

    /// Handles set_reminder and clear_reminder.
    @MainActor
    static func dispatchReminders(name: String, args: [String: Any], store: AppStateStore, batchID: UUID) async -> String {
        switch name {
        case Names.setReminder:
            return await setReminder(args: args, store: store, batchID: batchID)
        case Names.clearReminder:
            return clearReminder(args: args, store: store, batchID: batchID)
        default:
            return toolError("Unknown reminder tool: \(name)")
        }
    }

    // MARK: - set_reminder

    @MainActor
    private static func setReminder(args: [String: Any], store: AppStateStore, batchID: UUID) async -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let dateStr = args["date"] as? String else {
            return toolError("Missing 'date'")
        }
        let date = iso8601WithFractional.date(from: dateStr) ?? iso8601Basic.date(from: dateStr)
        guard let fireDate = date else {
            return toolError("Invalid date format — use ISO 8601 (e.g. 2025-06-15T09:00:00)")
        }

        // Parse optional recurrence — default to .none (one-shot) when omitted.
        let recurrenceRaw = args["recurrence"] as? String ?? "none"
        let recurrence = ItemRecurrence(rawValue: recurrenceRaw) ?? .none

        // One-shot reminders must be in the future; repeating ones are always valid.
        guard fireDate > Date() || recurrence != .none else {
            return toolError("Reminder date must be in the future")
        }

        let title = store.item(id: id)?.title ?? unknownItemTitle
        store.setReminderAt(id, date: fireDate)
        store.setRecurrence(id, recurrence: recurrence)
        await NotificationService.scheduleReminder(for: id, title: title, at: fireDate, recurrence: recurrence)

        let recurrenceSuffix = recurrence == .none ? "" : " (\(recurrence.label))"
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .reminderSet(itemID: id),
            summary: "Reminder set for \"\(truncated(title))\"\(recurrenceSuffix)"
        ))
        return toolSuccess(["id": idStr, "scheduled": dateStr, "recurrence": recurrence.rawValue])
    }

    // MARK: - clear_reminder

    @MainActor
    private static func clearReminder(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            return toolError("Invalid or missing 'id'")
        }
        guard let item = store.item(id: id) else {
            return toolError("Item not found")
        }
        guard let priorDate = item.reminderAt else {
            return toolError("Item has no reminder to clear")
        }
        store.setReminderAt(id, date: nil)
        store.setRecurrence(id, recurrence: .none)
        NotificationService.cancel(for: id)
        store.recordAgentActivity(.init(
            batchID: batchID,
            kind: .reminderCleared(itemID: id, priorDate: priorDate),
            summary: "Cleared reminder for \"\(truncated(item.title))\""
        ))
        return toolSuccess(["id": idStr])
    }
}
