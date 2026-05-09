@preconcurrency import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

/// Indexes user-visible domain objects into iOS Spotlight so they can be
/// surfaced from system search and from Siri. Tapping a result deep-links
/// back into the app via `NSUserActivity` of type `CSSearchableItemActionType`.
///
/// Strategy: a full idempotent re-index of `activeItems + activeNotes + activeMemories`
/// driven from `AppStateStore.init` and from each mutating store method. The data set
/// is small (UI-bounded by what fits in a single user's task list / journal),
/// so the cost of rebuilding the index per mutation is negligible compared to
/// the complexity of an incremental indexer.
///
/// Index lives in three domains:
///   - `Domain.items`    — todos / tasks (only `pending` items appear)
///   - `Domain.notes`    — journal-style notes (only non-deleted)
///   - `Domain.memories` — agent memories (only non-deleted)
///
/// Each domain is fully replaced on every reindex, so soft-deleted or completed
/// records disappear from search automatically.
@MainActor
enum SpotlightIndexer {
    nonisolated private static let logger = Logger.app("SpotlightIndexer")

    // MARK: - Domains

    enum Domain: String, CaseIterable {
        case items    = "com.podcastr.spotlight.items"
        case notes    = "com.podcastr.spotlight.notes"
        case memories = "com.podcastr.spotlight.memories"
    }

    // MARK: - Identifier scheme
    //
    // Spotlight identifiers are namespaced as "<domain-prefix>:<uuid>" so a
    // continuation handler can route back to the correct screen without
    // consulting Spotlight's own domain identifier.

    private static let itemPrefix   = "item:"
    private static let notePrefix   = "note:"
    private static let memoryPrefix = "memory:"

    static func itemIdentifier(_ id: UUID)   -> String { itemPrefix   + id.uuidString }
    static func noteIdentifier(_ id: UUID)   -> String { notePrefix   + id.uuidString }
    static func memoryIdentifier(_ id: UUID) -> String { memoryPrefix + id.uuidString }

    /// Decoded result from a Spotlight continuation activity.
    ///
    /// `Identifiable` lets this enum drive `.sheet(item:)` directly without
    /// a wrapper struct.  The `id` mirrors the prefixed-identifier format
    /// used by `SpotlightIndexer`'s `itemIdentifier` / `noteIdentifier` /
    /// `memoryIdentifier` helpers so it is collision-safe across cases.
    enum DeepLink: Equatable, Identifiable {
        case item(UUID)
        case note(UUID)
        case memory(UUID)

        /// Stable, collision-safe identifier for use with `.sheet(item:)`.
        ///
        /// Inline string literals are used intentionally — the `var id` getter
        /// is `nonisolated` (required by `Identifiable`) and therefore cannot
        /// reference `SpotlightIndexer`'s `@MainActor`-isolated `itemPrefix` /
        /// `notePrefix` / `memoryPrefix` constants.
        var id: String {
            switch self {
            case .item(let uuid):   return "item:"   + uuid.uuidString
            case .note(let uuid):   return "note:"   + uuid.uuidString
            case .memory(let uuid): return "memory:" + uuid.uuidString
            }
        }
    }

    /// Parses an identifier produced by this indexer back into a `DeepLink`.
    /// Returns nil for unknown / malformed values.
    static func deepLink(from identifier: String) -> DeepLink? {
        if identifier.hasPrefix(itemPrefix) {
            let raw = String(identifier.dropFirst(itemPrefix.count))
            return UUID(uuidString: raw).map(DeepLink.item)
        }
        if identifier.hasPrefix(notePrefix) {
            let raw = String(identifier.dropFirst(notePrefix.count))
            return UUID(uuidString: raw).map(DeepLink.note)
        }
        if identifier.hasPrefix(memoryPrefix) {
            let raw = String(identifier.dropFirst(memoryPrefix.count))
            return UUID(uuidString: raw).map(DeepLink.memory)
        }
        return nil
    }

    /// Convenience that pulls the Spotlight identifier out of a continuation
    /// `NSUserActivity` and decodes it.
    static func deepLink(from activity: NSUserActivity) -> DeepLink? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        return deepLink(from: id)
    }

    // MARK: - Reindex

    /// Replaces the contents of all three Spotlight domains with current state.
    /// Safe to call from any mutation site — idempotent, and the underlying
    /// `CSSearchableIndex` calls are non-blocking.
    static func reindex(state: AppState) {
        let items = state.items
            .filter { !$0.deleted && $0.status == .pending }
            .map(makeSearchable(from:))

        let notes = state.notes
            .filter { !$0.deleted }
            .map(makeSearchable(from:))

        let memories = state.agentMemories
            .filter { !$0.deleted }
            .map(makeSearchable(from:))

        let index = CSSearchableIndex.default()

        index.deleteSearchableItems(withDomainIdentifiers: [Domain.items.rawValue]) { error in
            if let error { logger.error("Failed to delete items domain: \(error, privacy: .public)") }
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { error in
                if let error { logger.error("Failed to index items: \(error, privacy: .public)") }
            }
        }

        index.deleteSearchableItems(withDomainIdentifiers: [Domain.notes.rawValue]) { error in
            if let error { logger.error("Failed to delete notes domain: \(error, privacy: .public)") }
            guard !notes.isEmpty else { return }
            index.indexSearchableItems(notes) { error in
                if let error { logger.error("Failed to index notes: \(error, privacy: .public)") }
            }
        }

        index.deleteSearchableItems(withDomainIdentifiers: [Domain.memories.rawValue]) { error in
            if let error { logger.error("Failed to delete memories domain: \(error, privacy: .public)") }
            guard !memories.isEmpty else { return }
            index.indexSearchableItems(memories) { error in
                if let error { logger.error("Failed to index memories: \(error, privacy: .public)") }
            }
        }
    }

    /// Removes everything this app has put into Spotlight. Useful when the
    /// user clears all data.
    static func clearAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: Domain.allCases.map(\.rawValue)
        ) { error in
            if let error { logger.error("Failed to clear Spotlight index: \(error, privacy: .public)") }
        }
    }

    // MARK: - Builders

    private static func makeSearchable(from item: Item) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = item.title
        attrs.contentDescription = itemDescription(for: item)
        attrs.contentCreationDate = item.createdAt
        attrs.contentModificationDate = item.updatedAt
        attrs.keywords = itemKeywords(for: item)

        return CSSearchableItem(
            uniqueIdentifier: itemIdentifier(item.id),
            domainIdentifier: Domain.items.rawValue,
            attributeSet: attrs
        )
    }

    /// Builds a human-readable Spotlight snippet for an item.
    ///
    /// Leads with the item's own `details` text when present, then appends
    /// the requester name (when present), priority flag, reminder date, color
    /// tag, and source so users can identify items from Spotlight results without
    /// opening the app.
    private static func itemDescription(for item: Item) -> String {
        var parts: [String] = []
        if !item.details.isEmpty { parts.append(item.details) }
        if let name = item.requestedByDisplayName { parts.append("From \(name)") }
        if item.isPriority { parts.append("Starred") }
        if item.isPinned { parts.append("Pinned") }
        if let reminder = item.reminderAt {
            parts.append("Reminder: \(reminder.shortDateTime)")
        }
        if item.colorTag != .none { parts.append("\(item.colorTag.label) label") }
        if let estLabel = item.estimatedDurationLabel { parts.append("Est. \(estLabel)") }
        switch item.source {
        case .agent: parts.append("Added by agent")
        case .voice: parts.append("Added by voice")
        case .manual: break
        }
        return parts.joined(separator: " · ")
    }

    /// Builds a keyword list that lets Spotlight match source, priority,
    /// reminder metadata, and color tag — not just the item title.
    private static func itemKeywords(for item: Item) -> [String] {
        var keywords = ["task", "todo", "item"]
        switch item.source {
        case .agent: keywords.append(contentsOf: ["agent", "ai"])
        case .voice: keywords.append("voice")
        case .manual: break
        }
        if item.isPriority { keywords.append(contentsOf: ["priority", "starred"]) }
        if item.isPinned { keywords.append("pinned") }
        if item.reminderAt != nil { keywords.append("reminder") }
        if item.colorTag != .none { keywords.append(item.colorTag.label.lowercased()) }
        if item.estimatedMinutes != nil { keywords.append(contentsOf: ["duration", "estimate"]) }
        return keywords
    }

    private static func makeSearchable(from note: Note) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        // Notes have no title, just text — use the first line as the title and
        // the full body as the description so Spotlight can match either.
        let firstLine = note.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? note.text
        attrs.title = firstLine
        attrs.contentDescription = note.text
        attrs.contentCreationDate = note.createdAt
        attrs.keywords = noteKeywords(for: note)

        return CSSearchableItem(
            uniqueIdentifier: noteIdentifier(note.id),
            domainIdentifier: Domain.notes.rawValue,
            attributeSet: attrs
        )
    }

    /// Builds keywords for a note, surfacing its kind alongside the base terms.
    private static func noteKeywords(for note: Note) -> [String] {
        var keywords = ["note", "journal", note.kind.rawValue]
        switch note.kind {
        case .reflection: keywords.append("reflection")
        case .systemEvent: keywords.append(contentsOf: ["system", "event", "log"])
        case .free: break
        }
        return keywords
    }

    /// Builds a Spotlight entry for an agent memory.
    ///
    /// Memories have no title — the first sentence (up to the first period or 60
    /// characters, whichever comes first) is used as the title so results are
    /// scannable, with the full content in the description for full-text matching.
    private static func makeSearchable(from memory: AgentMemory) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = memoryTitle(for: memory)
        attrs.contentDescription = memory.content
        attrs.contentCreationDate = memory.createdAt
        attrs.keywords = ["memory", "agent", "remember"]

        return CSSearchableItem(
            uniqueIdentifier: memoryIdentifier(memory.id),
            domainIdentifier: Domain.memories.rawValue,
            attributeSet: attrs
        )
    }

    /// Derives a short Spotlight headline from a memory's content.
    ///
    /// Prefers the text up to the first sentence-ending punctuation so the
    /// Spotlight card reads naturally. Falls back to a 60-character truncation
    /// when the content has no sentence boundary.
    private static func memoryTitle(for memory: AgentMemory) -> String {
        let content = memory.content.trimmed
        let sentenceEnd = content.firstIndex(where: { ".!?".contains($0) })
        if let end = sentenceEnd {
            let candidate = String(content[...end])
            if candidate.count <= 80 { return candidate }
        }
        if content.count <= 60 { return content }
        return String(content.prefix(60)) + "…"
    }
}
