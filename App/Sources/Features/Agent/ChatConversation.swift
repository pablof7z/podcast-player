import Foundation

/// One named conversation tracked by `ChatHistoryStore`. Each chat thread the
/// user starts is persisted as a separate `ChatConversation` so they can pick
/// up an older thread from the history sheet without losing context.
///
/// `title` is generated asynchronously by `AgentChatTitleGenerator` after the
/// first assistant text reply lands; the empty string means "not yet
/// generated" and the history UI falls back to a snippet of the first user
/// message in that case.
struct ChatConversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var isUpgraded: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        messages: [ChatMessage] = [],
        isUpgraded: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.isUpgraded = isUpgraded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// First user message text — used in the history list when `title` is empty.
    var firstUserSnippet: String {
        for msg in messages {
            if case .user = msg.role { return msg.text }
        }
        return ""
    }
}
