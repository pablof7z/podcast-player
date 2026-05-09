import Foundation

// TODO: LLM-generated wiki page in the style of nvk/llm-wiki. Pages may scope
// to a single podcast, a single episode, or a cross-episode topic. Backed by
// markdown content plus structured front-matter.

/// A single LLM-authored knowledge page.
struct WikiPage: Codable, Sendable, Identifiable, Hashable {
    /// Stable identifier.
    var id: UUID
    /// Human-readable title.
    var title: String
    /// Markdown body of the page.
    var body: String
    /// When this page was last regenerated.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}
