import Foundation

// MARK: - Wiki page

/// The synthesized, citation-grounded article that is the heart of the
/// LLM Wiki surface.
///
/// Pages are *compiled* from raw transcript spans by `WikiGenerator`,
/// persisted by `WikiStorage`, and rendered by `WikiPageView`. They live in
/// one of two scopes: the cross-podcast **global** library, or **per
/// podcast** when the synthesis is scoped to a single feed.
///
/// A page is *immutable on disk* in the sense that the user never edits
/// the JSON directly — the agent regenerates pages by writing a new
/// version atomically (see `WikiStorage.write`). The user *contests*
/// claims; regeneration honours those contests.
struct WikiPage: Codable, Hashable, Identifiable, Sendable {

    var id: UUID
    var slug: String
    var title: String
    var kind: WikiPageKind
    var scope: WikiScope
    var summary: String
    var sections: [WikiSection]
    var citations: [WikiCitation]
    var confidence: Double
    var generatedAt: Date
    var model: String
    var compileRevision: Int

    init(
        id: UUID = UUID(),
        slug: String,
        title: String,
        kind: WikiPageKind,
        scope: WikiScope,
        summary: String,
        sections: [WikiSection] = [],
        citations: [WikiCitation] = [],
        confidence: Double = 0.5,
        generatedAt: Date = Date(),
        model: String = "openai/gpt-4o",
        compileRevision: Int = 1
    ) {
        self.id = id
        self.slug = WikiPage.normalize(slug: slug)
        self.title = title
        self.kind = kind
        self.scope = scope
        self.summary = summary
        self.sections = sections
        self.citations = citations
        self.confidence = max(0, min(1, confidence))
        self.generatedAt = generatedAt
        self.model = model
        self.compileRevision = compileRevision
    }

    /// The flattened list of claims across all sections, ordered by
    /// section ordinal then in-section position. Useful for the verifier
    /// and for accessibility's "Claims" rotor.
    var allClaims: [WikiClaim] {
        sections
            .sorted { $0.ordinal < $1.ordinal }
            .flatMap(\.claims)
    }

    /// `true` when at least one claim references the supplied episode.
    func cites(episodeID: UUID) -> Bool {
        citations.contains { $0.episodeID == episodeID }
            || allClaims.contains { claim in
                claim.citations.contains { $0.episodeID == episodeID }
            }
    }

    // MARK: - Slug normalization

    /// Canonicalises the supplied string into a URL-safe slug. Lowercase,
    /// dash-separated, no diacritics, only `[a-z0-9-]` retained. Used
    /// both as the on-disk filename and as the dual-link target.
    static func normalize(slug: String) -> String {
        let folded = slug
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        var out = ""
        var lastWasDash = false
        for char in folded {
            if allowed.contains(char) {
                out.append(char)
                lastWasDash = char == "-"
            } else if char.isWhitespace || char == "_" {
                if !lastWasDash {
                    out.append("-")
                    lastWasDash = true
                }
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}

// MARK: - Page kind

/// The taxonomy of wiki pages. Every page is exactly one kind; the kind
/// drives the section layout chosen by `WikiGenerator` and the rendering
/// path picked by `WikiPageView`.
enum WikiPageKind: String, Codable, CaseIterable, Sendable {

    /// A topic page (e.g. "Ozempic"). The default and most common kind.
    case topic

    /// A person page — thin variant referencing UX-13 speaker profiles.
    case person

    /// A show-level summary page covering one podcast end-to-end.
    case show

    /// An index page (e.g. "All topics", "Recent edits") that aggregates
    /// references to other pages without owning unique content.
    case index

    /// Display-friendly short label.
    var displayName: String {
        switch self {
        case .topic: "Topic"
        case .person: "Person"
        case .show: "Show"
        case .index: "Index"
        }
    }
}

// MARK: - Wiki scope

/// Controls whether a page lives in the cross-podcast library or is
/// scoped to a single feed.
///
/// On disk, scope determines the parent directory under
/// `Application Support/podcastr/wiki/`.
enum WikiScope: Codable, Hashable, Sendable {

    case global
    case podcast(UUID)

    /// On-disk directory segment. Stable across renames so that a
    /// regenerated page lands beside its prior version.
    var pathComponent: String {
        switch self {
        case .global: "global"
        case .podcast(let id): "podcast/\(id.uuidString)"
        }
    }

    /// The podcast this scope is bound to, if any.
    var podcastID: UUID? {
        if case .podcast(let id) = self { return id }
        return nil
    }
}
