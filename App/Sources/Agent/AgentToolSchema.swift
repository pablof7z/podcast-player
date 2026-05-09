import Foundation

// MARK: - JSON Schema (OpenAI tool format)

extension AgentTools {
    /// OpenAI-compatible tool schema array, ready to embed in a chat-completions request.
    ///
    /// Add a new entry here whenever a new tool is added to `AgentTools.Names` / `dispatch`.
    @MainActor
    static var schema: [[String: Any]] {
        [
            tool(
                name: Names.createItem,
                description: "Create a new task or to-do item for the user.",
                properties: [
                    "title": ["type": "string", "description": "The task title"],
                    "is_priority": ["type": "boolean", "description": "Mark the task as priority (★). Defaults to false."],
                ],
                required: ["title"]
            ),
            tool(
                name: Names.setItemPriority,
                description: "Mark or unmark an existing task as priority.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "priority": ["type": "boolean", "description": "true to mark as priority, false to remove priority"],
                ],
                required: ["id", "priority"]
            ),
            tool(
                name: Names.updateItem,
                description: "Update an existing task's title and/or details. Use this to correct typos, refine the title, or add/edit supporting notes on a task.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "title": ["type": "string", "description": "The new title for the task (optional — omit to leave title unchanged)"],
                    "details": ["type": "string", "description": "Supporting notes, context, or sub-steps for the task. Pass an empty string to clear existing details."],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.markItemDone,
                description: "Mark a task as completed by its ID.",
                properties: ["id": ["type": "string", "description": "UUID of the item"]],
                required: ["id"]
            ),
            tool(
                name: Names.deleteItem,
                description: "Delete a task by its ID.",
                properties: ["id": ["type": "string", "description": "UUID of the item"]],
                required: ["id"]
            ),
            tool(
                name: Names.createNote,
                description: "Save a note or reflection.",
                properties: [
                    "text": ["type": "string", "description": "Note content"],
                    "kind": ["type": "string", "enum": ["free", "reflection"], "description": "Note type"],
                ],
                required: ["text"]
            ),
            tool(
                name: Names.recordMemory,
                description: "Save something important to remember about the user for future sessions.",
                properties: ["content": ["type": "string", "description": "The fact to remember"]],
                required: ["content"]
            ),
            tool(
                name: Names.setReminder,
                description: "Set a reminder notification for an existing task at a specific date and time. Optionally set a recurrence so the reminder repeats automatically.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "date": ["type": "string", "description": "ISO 8601 date-time string for the first (or only) fire (e.g. 2025-06-15T09:00:00). For recurring reminders this anchors the time-of-day and, for weekly/monthly, the weekday or day-of-month."],
                    "recurrence": [
                        "type": "string",
                        "enum": ["none", "daily", "weekdays", "weekly", "monthly"],
                        "description": "How often the reminder repeats. 'none' fires once (default). 'daily' fires every day at the same time. 'weekdays' fires Monday–Friday. 'weekly' fires once a week on the same weekday. 'monthly' fires once a month on the same day-of-month.",
                    ],
                ],
                required: ["id", "date"]
            ),
            tool(
                name: Names.clearReminder,
                description: "Cancel and remove an existing reminder from a task.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.findItems,
                description: "Search tasks by keyword. Use this to look up completed, dropped, or pending tasks that may not appear in the system context — for example, 'did I finish X?', 'find everything about Y', or 'show me dropped items'. Returns matching items with their IDs, details (when present), status, due_at (when set), reminder_at + recurrence (when a reminder exists), color_tag (when set), and estimated_minutes (when set) so you can reference them in follow-up tool calls.",
                properties: [
                    "query": ["type": "string", "description": "Case-insensitive substring to search for in item titles"],
                    "status": [
                        "type": "string",
                        "enum": ["pending", "done", "dropped", "all"],
                        "description": "Filter by status. Defaults to 'all'.",
                    ],
                    "limit": ["type": "integer", "description": "Maximum number of results to return (1–\(findItemsMaxLimit)). Defaults to \(findItemsDefaultLimit)."],
                ],
                required: ["query"]
            ),
            tool(
                name: Names.setDueDate,
                description: "Set a due date on an existing task. The due date is metadata-only (no notification is fired). When the date passes the task appears as overdue in the UI. Use this when the user mentions a deadline, a 'by' date, or asks to track when something is due.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "date": ["type": "string", "description": "ISO 8601 date string for the due date (e.g. 2025-06-15). Time component is ignored — the whole day counts."],
                ],
                required: ["id", "date"]
            ),
            tool(
                name: Names.clearDueDate,
                description: "Remove the due date from a task.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.addTag,
                description: "Add a tag to an existing task. Tags are short labels (e.g. 'work', 'home', 'urgent') that group items and enable quick filtering. Tags are stored lowercased.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "tag": ["type": "string", "description": "Tag to add (e.g. 'work', 'home'). Will be lowercased automatically."],
                ],
                required: ["id", "tag"]
            ),
            tool(
                name: Names.removeTag,
                description: "Remove a tag from an existing task.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "tag": ["type": "string", "description": "Tag to remove."],
                ],
                required: ["id", "tag"]
            ),
            tool(
                name: Names.setItemColorTag,
                description: "Set or clear a color label on an existing task. Color labels appear as a leading stripe in the UI and help the user visually group items. Use 'none' to remove an existing color.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "color_tag": [
                        "type": "string",
                        "enum": ItemColorTag.allCases.map(\.rawValue),
                        "description": "Color to apply. Use 'none' to remove the current color label.",
                    ],
                ],
                required: ["id", "color_tag"]
            ),
            tool(
                name: Names.setEstimatedMinutes,
                description: "Set an estimated completion time (in minutes) on a task. Use this when the user mentions how long something will take (e.g. '30 minute task', 'about an hour'). The estimate appears as a chip in the task list.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                    "minutes": ["type": "integer", "description": "Estimated number of minutes to complete the task (must be > 0)"],
                ],
                required: ["id", "minutes"]
            ),
            tool(
                name: Names.clearEstimatedMinutes,
                description: "Remove the estimated completion time from a task.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.pinItem,
                description: "Pin a task to the top of the list so it always appears above all other items, regardless of status or sort order. Use when the user wants something kept permanently visible.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.unpinItem,
                description: "Unpin a task, returning it to the normal sort order.",
                properties: [
                    "id": ["type": "string", "description": "UUID of the item"],
                ],
                required: ["id"]
            ),
            tool(
                name: Names.renameTag,
                description: "Rename a tag across all tasks. Every task that carries 'old_tag' will have it replaced with 'new_tag'. If a task already has 'new_tag', the duplicate is removed. Tags are lowercased automatically.",
                properties: [
                    "old_tag": ["type": "string", "description": "The existing tag name to rename (e.g. 'wrk')."],
                    "new_tag": ["type": "string", "description": "The replacement tag name (e.g. 'work'). Will be lowercased automatically."],
                ],
                required: ["old_tag", "new_tag"]
            ),
        ]
    }

    /// Builds an OpenAI-compatible function-tool dictionary.
    private static func tool(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }
}
