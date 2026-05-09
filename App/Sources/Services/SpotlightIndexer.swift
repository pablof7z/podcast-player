@preconcurrency import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

/// Indexes user-visible domain objects into iOS Spotlight so they can be
/// surfaced from system search and from Siri. Tapping a result deep-links
/// back into the app via `NSUserActivity` of type `CSSearchableItemActionType`.
///
/// Strategy: a full idempotent re-index of `activeNotes + activeMemories`
/// driven from `AppStateStore.init` and from each mutating store method. The
/// data set is small (UI-bounded by what fits in a single user's journal),
/// so the cost of rebuilding the index per mutation is negligible compared to
/// the complexity of an incremental indexer.
///
/// Index lives in two domains:
///   - `Domain.notes`    — journal-style notes (only non-deleted)
///   - `Domain.memories` — agent memories (only non-deleted)
///
/// Each domain is fully replaced on every reindex, so soft-deleted records
/// disappear from search automatically.
@MainActor
enum SpotlightIndexer {
    nonisolated private static let logger = Logger.app("SpotlightIndexer")

    // MARK: - Domains

    enum Domain: String, CaseIterable {
        case notes    = "com.podcastr.spotlight.notes"
        case memories = "com.podcastr.spotlight.memories"
    }

    // MARK: - Identifier scheme

    private static let notePrefix   = "note:"
    private static let memoryPrefix = "memory:"

    static func noteIdentifier(_ id: UUID)   -> String { notePrefix   + id.uuidString }
    static func memoryIdentifier(_ id: UUID) -> String { memoryPrefix + id.uuidString }

    /// Decoded result from a Spotlight continuation activity.
    enum DeepLink: Equatable, Identifiable {
        case note(UUID)
        case memory(UUID)

        /// Stable, collision-safe identifier for use with `.sheet(item:)`.
        var id: String {
            switch self {
            case .note(let uuid):   return "note:"   + uuid.uuidString
            case .memory(let uuid): return "memory:" + uuid.uuidString
            }
        }
    }

    /// Parses an identifier produced by this indexer back into a `DeepLink`.
    /// Returns nil for unknown / malformed values.
    static func deepLink(from identifier: String) -> DeepLink? {
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

    /// Replaces the contents of both Spotlight domains with current state.
    /// Safe to call from any mutation site — idempotent, and the underlying
    /// `CSSearchableIndex` calls are non-blocking.
    static func reindex(state: AppState) {
        let notes = state.notes
            .filter { !$0.deleted }
            .map(makeSearchable(from:))

        let memories = state.agentMemories
            .filter { !$0.deleted }
            .map(makeSearchable(from:))

        let index = CSSearchableIndex.default()

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

    private static func makeSearchable(from note: Note) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
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

    private static func noteKeywords(for note: Note) -> [String] {
        var keywords = ["note", "journal", note.kind.rawValue]
        switch note.kind {
        case .reflection: keywords.append("reflection")
        case .systemEvent: keywords.append(contentsOf: ["system", "event", "log"])
        case .free: break
        }
        return keywords
    }

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
