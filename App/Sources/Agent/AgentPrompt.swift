import Foundation

/// Builds the system prompt injected at position 0 of every agent run.
///
/// Surfaces a compact podcast inventory (subscriptions, in-progress
/// episodes, recent unplayed) so the agent can answer "what shows am I
/// subscribed to" or "what was I listening to" without spending a tool call.
/// Detailed drill-downs (transcripts, wiki, semantic search) still go
/// through tools.
///
/// Includes the friend list, recent notes, and persisted memories the
/// template ships with.
enum AgentPrompt {

    // Inventory caps — keep the prompt under a few KB even with a heavy library.
    private enum Cap {
        static let subscriptions = 30
        static let inProgress = 5
        static let recentUnplayed = 10
        static let recentWindowDays: Double = 7
        static let titleChars = 80
    }

    static func build(for state: AppState) -> String {
        var sections: [String] = []

        sections.append("""
        You are a helpful personal assistant embedded in a podcast-player iOS app.
        Today is \(Self.dateString).
        Help the user surface, recall, and reason about what they've been listening to.
        Be concise and action-oriented. For specifics that aren't in this prompt
        (transcripts, episode contents, semantic search), call your tools.
        """)

        if !state.subscriptions.isEmpty {
            let titles = state.subscriptions
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .prefix(Cap.subscriptions)
                .map { "- \(truncate($0.title))" }
                .joined(separator: "\n")
            let suffix = state.subscriptions.count > Cap.subscriptions
                ? "\n…and \(state.subscriptions.count - Cap.subscriptions) more"
                : ""
            sections.append("## Subscriptions (\(state.subscriptions.count))\n\(titles)\(suffix)")
        }

        let inProgress = state.episodes
            .filter { !$0.played && $0.playbackPosition > 0 }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(Cap.inProgress)
        if !inProgress.isEmpty {
            let lookup = subscriptionTitlesByID(state)
            let lines = inProgress.map { ep -> String in
                let show = lookup[ep.subscriptionID] ?? "Unknown show"
                return "- \(truncate(ep.title)) — \(show)"
            }.joined(separator: "\n")
            sections.append("## In Progress\n\(lines)")
        }

        let cutoff = Date().addingTimeInterval(-Cap.recentWindowDays * 86_400)
        let recentUnplayed = state.episodes
            .filter { !$0.played && $0.playbackPosition == 0 && $0.pubDate >= cutoff }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(Cap.recentUnplayed)
        if !recentUnplayed.isEmpty {
            let lookup = subscriptionTitlesByID(state)
            let lines = recentUnplayed.map { ep -> String in
                let show = lookup[ep.subscriptionID] ?? "Unknown show"
                return "- \(truncate(ep.title)) — \(show)"
            }.joined(separator: "\n")
            sections.append("## Recent (last \(Int(Cap.recentWindowDays)) days, unplayed)\n\(lines)")
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

    private static func subscriptionTitlesByID(_ state: AppState) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: state.subscriptions.map { ($0.id, $0.title) })
    }

    private static func truncate(_ s: String) -> String {
        s.count <= Cap.titleChars ? s : String(s.prefix(Cap.titleChars - 1)) + "…"
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
