import SwiftUI

// MARK: - HomeRelatedSheet
//
// "Find related across my library" — long-press affordance on a featured
// episode. Runs the existing `RAGService` over the user's transcript
// corpus using the seed episode's title + chapter titles as the query,
// dedupes by subscription, and surfaces matches from *other* shows. When
// RAG returns nothing (no transcripts indexed yet) we fall back to
// threading-topic matches via `ThreadingInferenceService`.

/// Half-sheet presented from the featured-section context menu.
struct HomeRelatedSheet: View {
    let seedEpisode: Episode
    let seedSubscription: PodcastSubscription?

    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var matches: [Match] = []

    private enum Phase: Equatable {
        case loading
        case ready
        case empty
    }

    struct Match: Identifiable, Equatable {
        let id: UUID
        let episode: Episode
        let subscription: PodcastSubscription?
        let snippet: String
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Related")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            Haptics.selection()
                            dismiss()
                        }
                    }
                }
                .task { await loadRelated() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                Text("Searching your library…")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ContentUnavailableView(
                "No related episodes",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Index a few transcripts first — they power cross-show matches.")
            )

        case .ready:
            List(matches) { match in
                NavigationLink {
                    EpisodeDetailView(episodeID: match.episode.id)
                } label: {
                    relatedRow(match)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    Haptics.selection()
                })
            }
            .listStyle(.plain)
        }
    }

    private func relatedRow(_ match: Match) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = match.subscription?.title, !title.isEmpty {
                    Text(title)
                        .font(AppTheme.Typography.caption)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(match.episode.title)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(2)
                if !match.snippet.isEmpty {
                    Text(match.snippet)
                        .font(AppTheme.Typography.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, AppTheme.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    // MARK: - Loading

    private func loadRelated() async {
        let query = buildQuery()
        let viaRAG = await searchRAG(query: query)
        if !viaRAG.isEmpty {
            matches = viaRAG
            phase = .ready
            return
        }
        let viaThreading = threadingMatches()
        if !viaThreading.isEmpty {
            matches = viaThreading
            phase = .ready
            return
        }
        phase = .empty
    }

    /// Compose the retrieval query: episode title plus any non-ad chapter
    /// titles. Ad-flagged chapters (`includeInTableOfContents == false`)
    /// are intentionally skipped — their text would just bias the search
    /// toward sponsor content.
    private func buildQuery() -> String {
        var parts: [String] = [seedEpisode.title]
        if let chapters = seedEpisode.chapters {
            let titles = chapters
                .filter { $0.includeInTableOfContents }
                .map(\.title)
                .filter { !$0.isEmpty }
            parts.append(contentsOf: titles.prefix(8))
        }
        return parts.joined(separator: " · ")
    }

    private func searchRAG(query: String) async -> [Match] {
        do {
            let opts = RAGSearch.Options(k: 12, hybrid: true, rerank: true)
            let chunkMatches = try await RAGService.shared.search.search(
                query: query,
                scope: nil,
                options: opts
            )
            // Dedupe by subscription + drop the seed itself. Take the
            // best-scored chunk per subscription so the sheet doesn't
            // collapse to "the same show, three times".
            var seenSubs: Set<UUID> = []
            seenSubs.insert(seedEpisode.subscriptionID)
            var collected: [Match] = []
            for chunk in chunkMatches {
                guard let ep = store.episode(id: chunk.chunk.episodeID),
                      ep.id != seedEpisode.id,
                      !seenSubs.contains(ep.subscriptionID) else { continue }
                seenSubs.insert(ep.subscriptionID)
                collected.append(Match(
                    id: ep.id,
                    episode: ep,
                    subscription: store.subscription(id: ep.subscriptionID),
                    snippet: String(chunk.chunk.text.prefix(220))
                ))
                if collected.count >= 8 { break }
            }
            return collected
        } catch {
            return []
        }
    }

    /// Fallback when no transcripts are indexed yet: surface episodes
    /// from threading topics that mention the seed episode. Cheap-but-
    /// useful: the user gets *something* even before they request
    /// transcript ingestion for any show.
    private func threadingMatches() -> [Match] {
        let mentions = store.state.threadingMentions
            .filter { $0.episodeID == seedEpisode.id }
        let topicIDs = Set(mentions.map(\.topicID))
        guard !topicIDs.isEmpty else { return [] }
        var seenSubs: Set<UUID> = [seedEpisode.subscriptionID]
        var collected: [Match] = []
        for topicID in topicIDs {
            for mention in store.threadingMentions(forTopic: topicID) {
                guard mention.episodeID != seedEpisode.id,
                      let ep = store.episode(id: mention.episodeID),
                      !seenSubs.contains(ep.subscriptionID) else { continue }
                seenSubs.insert(ep.subscriptionID)
                collected.append(Match(
                    id: ep.id,
                    episode: ep,
                    subscription: store.subscription(id: ep.subscriptionID),
                    snippet: mention.snippet
                ))
                if collected.count >= 8 { break }
            }
            if collected.count >= 8 { break }
        }
        return collected
    }
}
