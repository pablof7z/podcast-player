import Foundation

// MARK: - LLMScriptDraft

/// Minimal in-memory representation of what the LLM produced *before* the
/// composer attaches durations and persists it.
struct LLMScriptDraft: Sendable {
    var title: String
    var subtitle: String
    var segments: [BriefingSegment]
}

// MARK: - BriefingFixtureScript

/// Deterministic script the composer falls back to when no OpenRouter API
/// key is configured (the fixture path called out in the lane brief —
/// *"Real LLM/TTS calls stubbed — return fixture script + silent audio asset"*).
///
/// The fixture is opinionated rather than pretty: it produces a 4-segment
/// structure (intro · two body segments · outro) shaped like the W2 player
/// wireframe so previews and screenshots look right out of the box. It also
/// tries to thread real RAG candidates through as attributions and quotes so
/// downstream components see realistic data.
enum BriefingFixtureScript {

    static func make(
        request: BriefingRequest,
        candidates: [RAGCandidate]
    ) -> LLMScriptDraft {
        let titleText = title(for: request)
        let subtitleText = subtitle(for: request, candidates: candidates)

        let intro = BriefingSegment(
            index: 0,
            title: "Intro",
            bodyText: introBody(for: request),
            attributions: [],
            quotes: [],
            targetSeconds: 12
        )

        let body1 = makeBodySegment(
            index: 1,
            title: bodyTitle(for: request, position: 0),
            text: bodyText(for: request, position: 0),
            candidate: candidates.first,
            targetSeconds: bodyDurationBudget(request: request, segments: 4) * 1.4
        )

        let body2 = makeBodySegment(
            index: 2,
            title: bodyTitle(for: request, position: 1),
            text: bodyText(for: request, position: 1),
            candidate: candidates.dropFirst().first,
            targetSeconds: bodyDurationBudget(request: request, segments: 4) * 1.4
        )

        let outro = BriefingSegment(
            index: 3,
            title: "Outro",
            bodyText: outroBody(for: request),
            attributions: [],
            quotes: [],
            targetSeconds: 8
        )

        return LLMScriptDraft(
            title: titleText,
            subtitle: subtitleText,
            segments: [intro, body1, body2, outro]
        )
    }

    // MARK: Titles & subtitles

    private static func title(for request: BriefingRequest) -> String {
        switch request.style {
        case .morning:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return "\(f.string(from: request.requestedAt)) Briefing"
        case .weeklyTLDR:         return "This Week's TLDR"
        case .catchUpOnShow:      return "Catch-Up Briefing"
        case .topicAcrossLibrary: return request.freeformQuery.map { "On \($0)" } ?? "Topic Briefing"
        }
    }

    private static func subtitle(
        for request: BriefingRequest,
        candidates: [RAGCandidate]
    ) -> String {
        let episodeCount = Set(candidates.compactMap(\.episodeID)).count
        let length = request.length.displayLabel
        if episodeCount > 0 {
            return "\(length) · drawn from \(episodeCount) episode\(episodeCount == 1 ? "" : "s")"
        }
        return "\(length) · composed for you"
    }

    // MARK: Bodies

    private static func introBody(for request: BriefingRequest) -> String {
        switch request.style {
        case .morning:
            return "Good morning. Here's what's worth your attention today, drawn from the shows you follow."
        case .weeklyTLDR:
            return "Welcome back. Here's the week, condensed — the threads that matter, in the order they matter."
        case .catchUpOnShow:
            return "You've been away from this show. Here's the arc — the only chapters you need before pressing play again."
        case .topicAcrossLibrary:
            let topic = request.freeformQuery ?? "this topic"
            return "Here's what your podcasts have been saying about \(topic), reconciled into one story."
        }
    }

    private static func outroBody(for request: BriefingRequest) -> String {
        _ = request
        return "That's the briefing. Tap a segment to go deeper, or ask me to follow any thread."
    }

    private static func bodyTitle(
        for request: BriefingRequest,
        position: Int
    ) -> String {
        switch (request.style, position) {
        case (.morning, 0):            return "Today's headline"
        case (.morning, 1):            return "Threads to watch"
        case (.weeklyTLDR, 0):         return "The biggest story"
        case (.weeklyTLDR, 1):         return "What to listen to next"
        case (.catchUpOnShow, 0):      return "What you missed"
        case (.catchUpOnShow, 1):      return "Where it's heading"
        case (.topicAcrossLibrary, 0): return "Where they agree"
        case (.topicAcrossLibrary, 1): return "Where they disagree"
        default:                       return "Segment"
        }
    }

    private static func bodyText(
        for request: BriefingRequest,
        position: Int
    ) -> String {
        let topic = request.freeformQuery ?? "your shows"
        switch (request.style, position) {
        case (.morning, 0):
            return "The single thing worth your attention this morning is the cadence of recent conversation across your subscriptions. Hosts converged on the same handful of stories — that convergence is the story."
        case (.morning, 1):
            return "Three threads to watch: a hardware shift one of your tech shows is treating as inevitable, a health protocol the longevity hosts are revisiting, and a culture beat that crossed three of your shows in two days."
        case (.weeklyTLDR, 0):
            return "The week's biggest story was a hardware reveal that your tech podcasts treated as a turning point. Two of them led with it; a third made it the spine of the entire episode."
        case (.weeklyTLDR, 1):
            return "Pick one to listen to next: the longest-form take, in the show that always builds the most context. Skip the recap episodes — you've now heard the recap."
        case (.catchUpOnShow, 0):
            return "While you were away, the show pivoted on \(topic). Three episodes built on each other; the fourth complicated the thesis."
        case (.catchUpOnShow, 1):
            return "Where it's heading: the host has flagged a series, and the next two episodes are likely to land on a stronger conclusion than today's."
        case (.topicAcrossLibrary, 0):
            return "On \(topic), the hosts that disagree about almost everything actually align on the underlying mechanism. They argue about magnitude, not direction."
        case (.topicAcrossLibrary, 1):
            return "They split on prescription. One camp treats \(topic) as a tool; the other as a tell. The disagreement is downstream of how each defines the user."
        default:
            return "The hosts spent meaningful time on this; it earned the segment."
        }
    }

    private static func bodyDurationBudget(
        request: BriefingRequest,
        segments: Int
    ) -> TimeInterval {
        let total = request.length.targetSeconds
        return total / Double(max(2, segments - 2))
    }

    // MARK: Body assembly

    private static func makeBodySegment(
        index: Int,
        title: String,
        text: String,
        candidate: RAGCandidate?,
        targetSeconds: TimeInterval
    ) -> BriefingSegment {
        var attributions: [BriefingAttribution] = []
        var quotes: [BriefingQuote] = []
        if let c = candidate {
            attributions.append(BriefingAttribution(
                episodeID: c.episodeID,
                wikiPageID: c.wikiPageID,
                displayLabel: c.sourceLabel,
                timestampSeconds: c.startSeconds
            ))
            // Original-audio quotes can only be inserted when we know the
            // enclosure URL. Without that the briefing falls back to TTS-only.
            if let url = c.enclosureURL,
               let start = c.startSeconds,
               let end = c.endSeconds, let episodeID = c.episodeID, end > start {
                quotes.append(BriefingQuote(
                    episodeID: episodeID,
                    enclosureURL: url,
                    startSeconds: start,
                    endSeconds: end,
                    insertAfterChar: text.count,  // stitch quote at segment tail
                    transcriptText: c.text
                ))
            }
        }
        return BriefingSegment(
            index: index,
            title: title,
            bodyText: text,
            attributions: attributions,
            quotes: quotes,
            targetSeconds: targetSeconds
        )
    }
}
