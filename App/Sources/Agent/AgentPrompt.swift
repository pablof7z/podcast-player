import Foundation

/// Builds the system prompt injected at position 0 of every agent run.
/// Includes friend list and persisted memories.
enum AgentPrompt {
    static func build(for state: AppState) -> String {
        var sections: [String] = []

        sections.append("""
        You are a helpful personal assistant embedded in a podcast-player iOS app.
        Today is \(Self.dateString).
        Help the user surface, recall, and reason about what they've been listening to.
        Be concise and action-oriented.
        """)

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

    private static var dateString: String {
        dateFormatter.string(from: Date())
    }
}
