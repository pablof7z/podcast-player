import Foundation

// NOTE: Placeholder definition.
//
// The "real" `PodcastCategory` is being authored in parallel by the
// PodcastCategorizationService agent. This stub matches the agreed shape
// (id, name, slug, description, colorHex, subscriptionIDs, generatedAt,
// model) so the per-category settings UI can compile against it. The
// other agent's branch will replace this file when rebased; the field
// set is contract-stable so swapping the implementation should be
// transparent to consumers.

/// A grouping of subscriptions under a single thematic label
/// (e.g. "News", "Comedy", "Science").
///
/// Categories are produced by `PodcastCategorizationService` from the
/// subscription corpus, then persisted on `AppState.categories` so the
/// UI can present per-category settings without re-running the LLM.
struct PodcastCategory: Codable, Sendable, Identifiable, Hashable {
    /// Stable local UUID. Used as the key for `AppState.categorySettings`.
    var id: UUID
    /// Display name as surfaced to the user.
    var name: String
    /// Lowercase, dashed identifier suitable for analytics or routing.
    var slug: String
    /// Free-form description explaining what kinds of shows fall in here.
    var description: String
    /// Optional accent color (hex string, e.g. `#FF7A00`) for badges/chips.
    var colorHex: String?
    /// Subscription IDs the categorization service assigned to this group.
    var subscriptionIDs: [UUID]
    /// When the category set was generated.
    var generatedAt: Date
    /// LLM model identifier that produced this categorization.
    var model: String?

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        description: String = "",
        colorHex: String? = nil,
        subscriptionIDs: [UUID] = [],
        generatedAt: Date = Date(),
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.colorHex = colorHex
        self.subscriptionIDs = subscriptionIDs
        self.generatedAt = generatedAt
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, colorHex
        case subscriptionIDs, generatedAt, model
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        subscriptionIDs = try c.decodeIfPresent([UUID].self, forKey: .subscriptionIDs) ?? []
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }
}
