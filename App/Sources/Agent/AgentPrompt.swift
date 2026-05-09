import Foundation

/// Builds the system prompt injected at position 0 of every agent run.
/// Includes current state context, friend list, and persisted memories.
enum AgentPrompt {
    static func build(for state: AppState) -> String {
        var sections: [String] = []

        sections.append("""
        You are a helpful personal assistant embedded in an iOS app.
        Today is \(Self.dateString).
        Help the user manage their tasks, notes, and collaborate with their friends.
        Be concise and action-oriented.
        """)

        let activeItems = state.items
            .filter { !$0.deleted && $0.status == .pending }
            .sorted { $0.isPriority && !$1.isPriority }
        if !activeItems.isEmpty {
            let list = activeItems.map { item -> String in
                var line = "- [\(item.id)]"
                if item.isPriority { line += " ★" }
                if item.isPinned { line += " [pinned]" }
                line += " \(item.title)"
                if let name = item.requestedByDisplayName {
                    line += " (from \(name))"
                }
                if let due = item.dueAt {
                    let dueLabel = item.isOverdue ? "OVERDUE since \(Self.dueDateString(due))" : "due \(Self.dueDateString(due))"
                    line += " [\(dueLabel)]"
                }
                if let reminder = item.reminderAt {
                    let recurrenceLabel = item.recurrence != .none ? ", \(item.recurrence.label)" : ""
                    line += " [reminder: \(Self.reminderString(reminder))\(recurrenceLabel)]"
                }
                if !item.tags.isEmpty {
                    line += " [tags: \(item.tags.map { "#\($0)" }.joined(separator: ", "))]"
                }
                if item.colorTag != .none {
                    line += " [color: \(item.colorTag.rawValue)]"
                }
                if let estLabel = item.estimatedDurationLabel {
                    line += " [est: \(estLabel)]"
                }
                if !item.details.isBlank {
                    line += "\n  Details: \(item.details)"
                }
                return line
            }.joined(separator: "\n")
            sections.append("## Pending Items\n★ = priority\n\(list)")
        }

        if !state.friends.isEmpty {
            // Expose only displayName + truncated public identifier. Internal
            // UUIDs have no value to the LLM (no tool consumes a friend UUID),
            // and leaking them broadens the prompt-injection / data-exfiltration
            // surface unnecessarily.
            let list = state.friends
                .map { "- \($0.displayName) (\($0.shortIdentifier))" }
                .joined(separator: "\n")
            sections.append("## Friends\n\(list)")
        }

        let activeNotes = state.notes
            .filter { !$0.deleted && $0.kind != .systemEvent }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
        if !activeNotes.isEmpty {
            let list = activeNotes.map { "- \($0.text)" }.joined(separator: "\n")
            sections.append("## Notes\n\(list)")
        }

        let memories = state.agentMemories.filter { !$0.deleted }
        if !memories.isEmpty {
            let list = memories.map { "- \($0.content)" }.joined(separator: "\n")
            sections.append("## What You Know About the User\n\(list)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Cached formatter — DateFormatter is expensive to allocate and thread-safe for read after setup.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private static let reminderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static var dateString: String {
        dateFormatter.string(from: Date())
    }

    private static func dueDateString(_ date: Date) -> String {
        dueDateFormatter.string(from: date)
    }

    private static func reminderString(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "overdue (\(reminderFormatter.string(from: date)))" }
        let hours = interval / 3_600
        if hours < 24 {
            let h = Int(hours)
            return h == 0 ? "in less than an hour" : "in \(h)h (\(reminderFormatter.string(from: date)))"
        }
        return reminderFormatter.string(from: date)
    }
}
