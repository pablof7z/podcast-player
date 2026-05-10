import Foundation
import Observation
import os.log

// MARK: - AgentPicksService
//
// Curates the "agent picks" surface in the merged Home featured section.
// One LLM call per ~6 hours (or on material library change), cached in
// memory; degrades to a deterministic heuristic when no API key is set
// or the call fails.
//
// Design notes:
//   - We do NOT reuse `AgentChatSession`'s tool loop. The picks need
//     exactly one structured-JSON response from the model — instrumenting
//     the full chat-history + tool-dispatch pipeline would be wasted work
//     and would fight the cache (every send mutates session history).
//   - Cache key combines time + a cheap fingerprint over the inputs the
//     prompt actually depends on. If the user marks several episodes
//     played the picks should refresh sooner than the 6-hour TTL — we'd
//     rather recompute than surface a pick the user already finished.
//   - Fallback heuristic ("rarely-opened shows"): the store does not
//     track per-show open counts. As a defensible v1 proxy we pick the
//     three subscriptions whose newest unplayed episode is the LEAST
//     recent — i.e. shows the user appears to have neglected — and take
//     the newest unplayed episode from each.

@MainActor
@Observable
final class AgentPicksService {

    static let shared = AgentPicksService()

    private static let logger = Logger.app("AgentPicksService")

    /// Cache TTL. The brief asks for ~6 hours; we honour it as the upper
    /// bound. The fingerprint check below can invalidate sooner.
    static let cacheTTL: TimeInterval = 6 * 3_600

    /// Soft cap on subscriptions enumerated in the prompt. Picks against
    /// a 200-show library otherwise blow past sensible token budgets.
    private static let promptSubscriptionCap = 30

    /// Latest known bundle. Drives the view layer; updated atomically
    /// so SwiftUI re-renders once when a refresh completes.
    private(set) var bundle: HomeAgentPicksBundle = .empty

    /// `true` while a network refresh is in flight. View shows a
    /// shimmer/placeholder when this is set and `bundle.picks.isEmpty`.
    private(set) var isRefreshing: Bool = false

    /// Fingerprint captured when the current `bundle` was generated. The
    /// next refresh checks this to decide whether the cached bundle is
    /// still semantically valid.
    private var lastFingerprint: PicksFingerprint?
    private var refreshTask: Task<Void, Never>?

    init() {}

    /// Trigger a refresh if the cache is stale. Cheap to call from
    /// `.task`; coalesces concurrent calls into a single network turn.
    func ensureFreshPicks(store: AppStateStore, now: Date = Date()) {
        let fingerprint = makeFingerprint(store: store)
        if shouldUseCache(now: now, fingerprint: fingerprint) {
            return
        }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh(store: store, fingerprint: fingerprint, now: now)
        }
    }

    /// Discard the cache so the next `ensureFreshPicks` makes a fresh
    /// call. Used by the manual "Refresh picks" affordance.
    func invalidate() {
        bundle = .empty
        lastFingerprint = nil
    }

    // MARK: - Refresh

    private func refresh(store: AppStateStore, fingerprint: PicksFingerprint, now: Date) async {
        defer {
            refreshTask = nil
            isRefreshing = false
        }
        isRefreshing = true

        let inputs = collectInputs(store: store)
        guard !inputs.unplayed.isEmpty else {
            bundle = .empty
            lastFingerprint = fingerprint
            return
        }

        if hasAPIKey(model: store.state.settings.llmModel) {
            do {
                let picks = try await runLLMPicks(store: store, inputs: inputs)
                if !picks.isEmpty {
                    bundle = HomeAgentPicksBundle(picks: picks, source: .agent, generatedAt: now)
                    lastFingerprint = fingerprint
                    return
                }
            } catch {
                Self.logger.error("Agent picks LLM call failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback heuristic — rarely-opened shows proxied via stalest
        // newest-unplayed. The view surfaces these without the agent
        // rationale styling so the source is honest to the user.
        let fallback = AgentPicksFallback.derive(inputs: inputs)
        bundle = HomeAgentPicksBundle(picks: fallback, source: .fallback, generatedAt: now)
        lastFingerprint = fingerprint
    }

    // MARK: - Cache decision

    private func shouldUseCache(now: Date, fingerprint: PicksFingerprint) -> Bool {
        guard !bundle.picks.isEmpty else { return false }
        guard let last = lastFingerprint, last == fingerprint else { return false }
        return now.timeIntervalSince(bundle.generatedAt) < Self.cacheTTL
    }

    private func makeFingerprint(store: AppStateStore) -> PicksFingerprint {
        // Cheap stable signature: subscription count + (count, newest pubDate)
        // of unplayed episodes. Marking an episode played changes the unplayed
        // count and bumps the fingerprint — exactly the case we want to refresh.
        let unplayed = store.state.episodes.filter { !$0.played }
        let newest = unplayed.map(\.pubDate).max() ?? .distantPast
        return PicksFingerprint(
            subscriptionCount: store.state.subscriptions.count,
            unplayedCount: unplayed.count,
            newestUnplayed: newest
        )
    }

    // MARK: - Inputs

    private func collectInputs(store: AppStateStore) -> AgentPicksInputs {
        let unplayed = store.recentEpisodes(limit: 30)
        let inProgress = store.inProgressEpisodes
        let memories = store.state.agentMemories.filter { !$0.deleted }.prefix(10).map(\.content)
        let topics = store.threadingTopics
            .prefix(3)
            .map { $0.displayName }
        let lookup = Dictionary(
            uniqueKeysWithValues: store.state.subscriptions.map { ($0.id, $0.title) }
        )
        return AgentPicksInputs(
            unplayed: unplayed,
            inProgress: inProgress,
            subscriptionTitles: lookup,
            memorySnippets: Array(memories),
            topicNames: Array(topics)
        )
    }

    // MARK: - LLM call

    private func hasAPIKey(model: String) -> Bool {
        let reference = LLMModelReference(storedID: model)
        return LLMProviderCredentialResolver.hasAPIKey(for: reference.provider)
    }

    private func runLLMPicks(
        store: AppStateStore,
        inputs: AgentPicksInputs
    ) async throws -> [HomeAgentPick] {
        let prompt = AgentPicksPrompt.build(inputs: inputs)
        let messages: [[String: Any]] = [
            ["role": "system", "content": AgentPicksPrompt.systemInstruction],
            ["role": "user", "content": prompt]
        ]
        let result = try await AgentLLMClient.streamCompletion(
            messages: messages,
            tools: [],
            model: store.state.settings.llmModel,
            feature: CostFeature.agentChat,
            onPartialContent: { _ in }
        )
        let text = (result.assistantMessage["content"] as? String) ?? ""
        return AgentPicksPrompt.parse(text, knownEpisodeIDs: Set(inputs.unplayed.map(\.id) + inputs.inProgress.map(\.id)))
    }
}

// MARK: - Cache fingerprint

private struct PicksFingerprint: Equatable, Sendable {
    let subscriptionCount: Int
    let unplayedCount: Int
    let newestUnplayed: Date
}

// MARK: - Inputs to both LLM + fallback

struct AgentPicksInputs: Sendable {
    let unplayed: [Episode]
    let inProgress: [Episode]
    let subscriptionTitles: [UUID: String]
    let memorySnippets: [String]
    let topicNames: [String]
}

// MARK: - Fallback heuristic

enum AgentPicksFallback {

    /// Pick up to 3 episodes from the "rarely opened" shows: rank
    /// subscriptions by their newest unplayed episode's `pubDate`
    /// ascending (stalest first), then take the newest unplayed
    /// episode from each of the top 3. The first becomes the hero.
    ///
    /// The heuristic isn't a true open-count — the store doesn't track
    /// opens — but it surfaces the same UX outcome ("here's a show you
    /// haven't been listening to") without adding a new persistence
    /// surface for v1.
    static func derive(inputs: AgentPicksInputs) -> [HomeAgentPick] {
        guard !inputs.unplayed.isEmpty else { return [] }

        // newest-unplayed per show
        var newestPerShow: [UUID: Episode] = [:]
        for ep in inputs.unplayed {
            if let existing = newestPerShow[ep.subscriptionID] {
                if ep.pubDate > existing.pubDate {
                    newestPerShow[ep.subscriptionID] = ep
                }
            } else {
                newestPerShow[ep.subscriptionID] = ep
            }
        }

        // Stalest first: the show whose freshest unplayed episode is the
        // *oldest* is the show the user has been ignoring the longest.
        let sorted = newestPerShow.values.sorted { $0.pubDate < $1.pubDate }
        let top = Array(sorted.prefix(3))

        return top.enumerated().map { idx, ep in
            let showName = inputs.subscriptionTitles[ep.subscriptionID] ?? "this show"
            return HomeAgentPick(
                episodeID: ep.id,
                rationale: "From \(showName) — you haven't tuned in for a while.",
                isHero: idx == 0
            )
        }
    }
}
