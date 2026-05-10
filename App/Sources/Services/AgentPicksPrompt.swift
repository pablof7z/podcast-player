import Foundation

// MARK: - AgentPicksPrompt
//
// Prompt construction + JSON-response parsing for `AgentPicksService`. Lives
// next to the service but in its own file so prompt iteration doesn't churn
// the service's diff and the file-length cap stays intact.

enum AgentPicksPrompt {

    static let systemInstruction = """
    You are a podcast curation assistant. Given the user's recent listening
    history, persistent memories, active threading topics, and the unplayed
    episodes across their subscriptions, pick episodes worth listening to next.

    Reply with STRICT JSON only — no prose, no markdown fences. Shape:

      {
        "hero": {
          "episode_id": "<UUID>",
          "reason": "<two-sentence reason>",
          "spoken_reason": "<2-3 sentence spoken variant, ≤30 words>"
        },
        "secondaries": [
          { "episode_id": "<UUID>", "reason": "<one-sentence reason>" },
          { "episode_id": "<UUID>", "reason": "<one-sentence reason>" }
        ]
      }

    Rules:
      • Pick exactly one hero and zero, one, or two secondaries.
      • Every episode_id MUST appear verbatim in the candidate list below.
      • Hero reason: 2 sentences (~140 chars total).
      • Hero spoken_reason: 2–3 sentences, ≤30 words, conversational tone
        because it will be read aloud by a TTS voice. Avoid bullet points,
        URLs, em-dashes, or anything that doesn't read naturally.
      • Secondary reason: 1 sentence (~80 chars). No spoken_reason needed
        for secondaries.
      • Reasons should reference what the user cares about (memories, topics,
        in-progress shows) — not just "you might like this."
      • Emit `hero` FIRST in your JSON output, then `secondaries`. This
        ordering lets the client surface the hero before the secondaries
        have arrived in the stream.
    """

    static func build(inputs: AgentPicksInputs) -> String {
        var sections: [String] = []

        if !inputs.inProgress.isEmpty {
            let lines = inputs.inProgress.prefix(5).map {
                let show = inputs.subscriptionTitles[$0.subscriptionID] ?? "?"
                return "- \(show): \($0.title)"
            }.joined(separator: "\n")
            sections.append("## In-progress\n\(lines)")
        }

        if !inputs.memorySnippets.isEmpty {
            let lines = inputs.memorySnippets.prefix(8).map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Memories\n\(lines)")
        }

        if !inputs.topicNames.isEmpty {
            let lines = inputs.topicNames.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Active topics\n\(lines)")
        }

        // Cap at 30 candidates so the prompt stays under a reasonable token
        // budget — picks are over the freshest few, not the whole back catalog.
        let candidates = inputs.unplayed.prefix(30).map { ep -> String in
            let show = inputs.subscriptionTitles[ep.subscriptionID] ?? "?"
            let dur = ep.duration.map { " (\(Int($0/60)) min)" } ?? ""
            return "- id=\(ep.id.uuidString) — \(show): \(ep.title)\(dur)"
        }.joined(separator: "\n")
        sections.append("## Candidate episodes (use ids verbatim)\n\(candidates)")

        sections.append("Reply with the JSON object now.")
        return sections.joined(separator: "\n\n")
    }

    /// Parse the model's reply. Tolerant: strips markdown fences, finds
    /// the first balanced JSON object, validates each `episode_id` against
    /// the candidate set, and silently drops malformed entries.
    static func parse(_ raw: String, knownEpisodeIDs: Set<UUID>) -> [HomeAgentPick] {
        guard let data = extractJSONData(from: raw) else { return [] }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var picks: [HomeAgentPick] = []
        if let hero = dict["hero"] as? [String: Any],
           let idStr = hero["episode_id"] as? String,
           let id = UUID(uuidString: idStr),
           knownEpisodeIDs.contains(id) {
            let reason = (hero["reason"] as? String) ?? ""
            let spoken = (hero["spoken_reason"] as? String) ?? ""
            picks.append(HomeAgentPick(
                episodeID: id,
                rationale: reason,
                spokenRationale: spoken,
                isHero: true
            ))
        }
        if let seconds = dict["secondaries"] as? [[String: Any]] {
            for entry in seconds.prefix(2) {
                guard let idStr = entry["episode_id"] as? String,
                      let id = UUID(uuidString: idStr),
                      knownEpisodeIDs.contains(id) else { continue }
                let reason = (entry["reason"] as? String) ?? ""
                let spoken = (entry["spoken_reason"] as? String) ?? ""
                picks.append(HomeAgentPick(
                    episodeID: id,
                    rationale: reason,
                    spokenRationale: spoken,
                    isHero: false
                ))
            }
        }
        return picks
    }

    /// Locate the first balanced `{...}` JSON object in `raw`. Some models
    /// wrap the JSON in markdown fences or add prose; the brace-matcher
    /// extracts just the object so the JSON deserializer never sees the
    /// surrounding noise.
    private static func extractJSONData(from raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstBrace = trimmed.firstIndex(of: "{") else { return nil }
        var depth = 0
        var endIdx: String.Index?
        for idx in trimmed[firstBrace...].indices {
            let ch = trimmed[idx]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { endIdx = idx; break }
            }
        }
        guard let endIdx else { return nil }
        return String(trimmed[firstBrace...endIdx]).data(using: .utf8)
    }
}
