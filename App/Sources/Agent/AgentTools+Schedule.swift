import Foundation

// MARK: - Schedule tool handlers

extension AgentTools {

    @MainActor
    static func dispatchSchedule(name: String, args: [String: Any], store: AppStateStore) -> String {
        switch name {
        case Names.scheduleTask:        return scheduleTaskTool(args: args, store: store)
        case Names.cancelScheduledTask: return cancelScheduledTaskTool(args: args, store: store)
        case Names.listScheduledTasks:  return listScheduledTasksTool(store: store)
        default:                        return toolError("Unknown schedule tool: \(name)")
        }
    }

    @MainActor
    private static func scheduleTaskTool(args: [String: Any], store: AppStateStore) -> String {
        guard let prompt = args["prompt"] as? String, !prompt.isEmpty else {
            return toolError("'prompt' is required")
        }
        let title = (args["label"] as? String) ?? String(prompt.prefix(40))
        guard let schedule = scheduleString(from: args) else {
            return toolError("Either 'interval_seconds' or 'cadence' is required.")
        }
        switch store.createScheduledPromptTask(title: title, prompt: prompt, schedule: schedule) {
        case .accepted:
            return toolSuccess([
                "title": title,
                "schedule": schedule,
                "prompt": prompt,
            ])
        case .failure(let message):
            return toolError(message)
        }
    }

    @MainActor
    private static func cancelScheduledTaskTool(args: [String: Any], store: AppStateStore) -> String {
        guard let id = args["task_id"] as? String, !id.isEmpty else {
            return toolError("'task_id' is required.")
        }
        guard store.scheduledTasks.contains(where: { $0.id == id }) else {
            return toolError("No scheduled task found with id '\(id)'.")
        }
        switch store.removeScheduledTask(id: id) {
        case .accepted:
            return toolSuccess()
        case .failure(let message):
            return toolError(message)
        }
    }

    @MainActor
    private static func listScheduledTasksTool(store: AppStateStore) -> String {
        let tasks = store.scheduledTasks
        let list: [[String: Any]] = tasks.map { task in
            var entry: [String: Any] = [
                "task_id": task.id,
                "title": task.title,
                "schedule": task.schedule,
                "status": task.status,
                "enabled": task.isEnabled,
                "intent_type": task.intentType ?? "custom",
                "intent_label": task.intentLabel ?? "Custom task",
            ]
            if let detail = task.intentDetail {
                entry["intent_detail"] = detail
            }
            if let description = task.description {
                entry["description"] = description
            }
            if let nextRunAt = task.nextRunAt {
                entry["next_run_at"] = nextRunAt
            }
            if let lastRunAt = task.lastRunAt {
                entry["last_run_at"] = lastRunAt
            }
            return entry
        }
        return toolSuccess(["tasks": list, "count": tasks.count])
    }

    private static func scheduleString(from args: [String: Any]) -> String? {
        if let cadence = args["cadence"] as? String {
            switch cadence {
            case "hourly", "daily", "weekly": return cadence
            default: return nil
            }
        }
        let seconds: Int?
        if let value = args["interval_seconds"] as? Int {
            seconds = value
        } else if let value = args["interval_seconds"] as? Double {
            seconds = Int(value)
        } else {
            seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        switch seconds {
        case 3_600: return "hourly"
        case 86_400: return "daily"
        case 604_800: return "weekly"
        default: return "every \(seconds)s"
        }
    }
}
