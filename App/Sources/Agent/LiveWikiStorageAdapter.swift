import Foundation

// MARK: - LiveWikiStorageAdapter

/// Wraps `WikiStorage.shared` so the agent's `query_wiki` tool can find pages
/// by topic across titles, summaries, and claim bodies without dragging the
/// caller through the inventory + JSON-decode dance.
struct LiveWikiStorageAdapter: WikiStorageProtocol {

    let storage: WikiStorage

    init(storage: WikiStorage = .shared) {
        self.storage = storage
    }

    func queryWiki(topic: String, scope: PodcastID?, limit: Int) async throws -> [WikiHit] {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let scopeFilter: WikiScope? = scope.flatMap { UUID(uuidString: $0) }.map { .podcast($0) }
        let storage = storage
        let queryTokens = Self.tokenize(trimmed)
        let boundedLimit = max(1, limit)
        return try await Task.detached(priority: .utility) {
            let pages = try storage.allPages()
            let scored = pages.compactMap { page -> (page: WikiPage, score: Double, excerpt: String)? in
                if let scopeFilter, page.scope != scopeFilter { return nil }
                let score = Self.score(page: page, query: trimmed, tokens: queryTokens)
                guard score > 0 else { return nil }
                return (page, score, Self.excerpt(from: page, query: trimmed, tokens: queryTokens))
            }
            let filtered = scored
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return $0.page.generatedAt > $1.page.generatedAt
                }
                .prefix(boundedLimit)
            return filtered.map { hit in
                WikiHit(
                    pageID: hit.page.id.uuidString,
                    title: hit.page.title,
                    excerpt: String(hit.excerpt.prefix(280)),
                    score: hit.score
                )
            }
        }.value
    }

    private static func score(page: WikiPage, query: String, tokens: Set<String>) -> Double {
        let title = page.title.lowercased()
        let summary = page.summary.lowercased()
        let claims = page.allClaims.map { $0.text.lowercased() }
        var score = 0.0
        if title == query { score += 12 }
        if title.contains(query) { score += 8 }
        if summary.contains(query) { score += 5 }
        score += Double(claims.filter { $0.contains(query) }.count) * 4
        let corpusTokens = tokenize(([page.title, page.summary] + page.allClaims.map(\.text)).joined(separator: " "))
        let overlap = tokens.intersection(corpusTokens).count
        score += Double(overlap)
        return score
    }

    private static func excerpt(from page: WikiPage, query: String, tokens: Set<String>) -> String {
        let candidates = [page.summary] + page.allClaims.map(\.text)
        if let exact = candidates.first(where: { $0.lowercased().contains(query) }) {
            return exact
        }
        let best = candidates.max { lhs, rhs in
            tokenScore(lhs, tokens: tokens) < tokenScore(rhs, tokens: tokens)
        }
        if let best, !best.isBlank { return best }
        return page.summary
    }

    private static func tokenScore(_ text: String, tokens: Set<String>) -> Int {
        tokens.intersection(tokenize(text)).count
    }

    private static func tokenize(_ text: String) -> Set<String> {
        Set(text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 })
    }
}
