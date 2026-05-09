import Foundation

// MARK: - Wiki section

/// A single editorial section inside a `WikiPage` (e.g. "Definition",
/// "Consensus", "Contradictions", "Citations").
///
/// Sections own their own list of claims so the UI can render confidence
/// rules in the margin per-claim, not per-page. The verification pass walks
/// claims independently and may strip individual claims while leaving
/// surrounding section copy intact.
struct WikiSection: Codable, Hashable, Identifiable, Sendable {

    var id: UUID
    var heading: String
    var kind: WikiSectionKind
    var ordinal: Int
    var claims: [WikiClaim]

    /// Optional editor's note rendered in caption type below the heading.
    /// Used for *e.g.* "1 source" or "uncorroborated" annotations.
    var editorialNote: String?

    init(
        id: UUID = UUID(),
        heading: String,
        kind: WikiSectionKind,
        ordinal: Int,
        claims: [WikiClaim] = [],
        editorialNote: String? = nil
    ) {
        self.id = id
        self.heading = heading
        self.kind = kind
        self.ordinal = ordinal
        self.claims = claims
        self.editorialNote = editorialNote
    }

    /// Whether the section has at least one claim that survived the
    /// verification pass. Empty sections are dropped from the rendered
    /// output but kept in the model so a regen can repopulate them.
    var hasContent: Bool {
        !claims.contains(where: \.text.isEmpty) && !claims.isEmpty
    }
}

// MARK: - Section kind

/// The semantic role a section plays inside a topic page. Used to drive
/// editorial layout (split columns for consensus vs. contradictions, time
/// strips for evolution, etc.) without fragile string comparisons.
enum WikiSectionKind: String, Codable, CaseIterable, Sendable {
    case definition
    case whoDiscusses
    case evolution
    case consensus
    case contradictions
    case related
    case citations
    case freeform
}

// MARK: - Wiki claim

/// A single claim — a sentence (or short paragraph) the synthesizer
/// attributed to one or more citations.
///
/// A claim with `citations.isEmpty == true` is considered *unsourced* and
/// must either be tagged `[general knowledge]` (in a `definition` section
/// only) or dropped by the verification pass.
struct WikiClaim: Codable, Hashable, Identifiable, Sendable {

    var id: UUID
    var text: String
    var citations: [WikiCitation]
    var confidence: WikiConfidenceBand
    var isContestedByUser: Bool
    var isGeneralKnowledge: Bool

    init(
        id: UUID = UUID(),
        text: String,
        citations: [WikiCitation] = [],
        confidence: WikiConfidenceBand = .medium,
        isContestedByUser: Bool = false,
        isGeneralKnowledge: Bool = false
    ) {
        self.id = id
        self.text = text
        self.citations = citations
        self.confidence = confidence
        self.isContestedByUser = isContestedByUser
        self.isGeneralKnowledge = isGeneralKnowledge
    }

    /// `true` when the claim has no provenance and is not flagged as
    /// general knowledge — these are dropped by the verifier.
    var isUnsourced: Bool {
        citations.isEmpty && !isGeneralKnowledge
    }
}
