import Foundation

// MARK: - Wiki mock fixture

/// Deterministic sample pages used by SwiftUI previews, the wiki home
/// empty state, and the "generate page" sheet during the lane-7 stub
/// phase. Real generator output replaces these once Lane 6's RAG store
/// and an OpenRouter key are wired in.
enum WikiMockFixture {

    // MARK: - Stable fixture IDs

    /// Pinned UUIDs so previews and tests can compare against fixtures
    /// without churn each time the file is reloaded.
    enum FixtureID {
        static let ozempicEpisode = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        static let ozempicEpisode2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        static let mitochondriaEpisode = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        static let hubermanPodcast = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        static let attiaPodcast = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    }

    // MARK: - Pages

    /// Fully-populated topic page mirroring UX-04 §6b ("Ozempic").
    static let ozempicTopic: WikiPage = {
        let definition = WikiSection(
            heading: "Definition",
            kind: .definition,
            ordinal: 0,
            claims: [
                WikiClaim(
                    text: "Ozempic is a semaglutide-based GLP-1 receptor agonist originally approved for type-2 diabetes; off-label weight-loss use exploded in 2023, driven by social-media virality.",
                    citations: [
                        WikiCitation(
                            episodeID: FixtureID.ozempicEpisode,
                            startMS: 2_832_000,
                            endMS: 2_844_000,
                            quoteSnippet: "the uncoupling effect on mitochondria is what people miss",
                            speaker: "Andrew Huberman",
                            verificationConfidence: .high
                        )
                    ],
                    confidence: .high
                )
            ]
        )

        let consensus = WikiSection(
            heading: "Consensus",
            kind: .consensus,
            ordinal: 1,
            claims: [
                WikiClaim(
                    text: "Effective for short-term weight loss across multiple cohorts.",
                    citations: [
                        WikiCitation(
                            episodeID: FixtureID.ozempicEpisode2,
                            startMS: 724_000,
                            endMS: 750_000,
                            quoteSnippet: "the trial data on short-term loss is unambiguous",
                            speaker: "Peter Attia",
                            verificationConfidence: .high
                        )
                    ],
                    confidence: .high
                ),
                WikiClaim(
                    text: "Reduces visceral fat in addition to subcutaneous fat.",
                    citations: [
                        WikiCitation(
                            episodeID: FixtureID.ozempicEpisode2,
                            startMS: 1_220_000,
                            endMS: 1_245_000,
                            quoteSnippet: "we see visceral fat respond first",
                            speaker: "Peter Attia",
                            verificationConfidence: .medium
                        )
                    ],
                    confidence: .medium
                )
            ]
        )

        let contradictions = WikiSection(
            heading: "Contradictions",
            kind: .contradictions,
            ordinal: 2,
            claims: [
                WikiClaim(
                    text: "Long-term safety remains contested across the library.",
                    citations: [
                        WikiCitation(
                            episodeID: FixtureID.ozempicEpisode2,
                            startMS: 4_900_000,
                            endMS: 4_932_000,
                            quoteSnippet: "I'd want to see decades, not quarters",
                            speaker: "Peter Attia",
                            verificationConfidence: .high
                        ),
                        WikiCitation(
                            episodeID: FixtureID.ozempicEpisode,
                            startMS: 5_180_000,
                            endMS: 5_208_000,
                            quoteSnippet: "this stuff is everywhere and nobody knows",
                            speaker: "Joe Rogan",
                            verificationConfidence: .medium
                        )
                    ],
                    confidence: .medium
                )
            ]
        )

        let citations = WikiSection(
            heading: "Citations",
            kind: .citations,
            ordinal: 3,
            claims: []
        )

        let allCitations = [definition, consensus, contradictions]
            .flatMap { $0.claims.flatMap(\.citations) }

        return WikiPage(
            slug: "ozempic",
            title: "Ozempic",
            kind: .topic,
            scope: .global,
            summary: "Semaglutide-based GLP-1 agonist; library covers efficacy, safety debates, and cultural surge.",
            sections: [definition, consensus, contradictions, citations],
            citations: allCitations,
            confidence: 0.78,
            generatedAt: Date().addingTimeInterval(-3_600 * 8),
            model: "openai/gpt-4o-mini",
            compileRevision: 4
        )
    }()

    /// A second topic page so the home renders a list, not a single row.
    static let mitochondriaTopic: WikiPage = WikiPage(
        slug: "mitochondrial-uncoupling",
        title: "Mitochondrial Uncoupling",
        kind: .topic,
        scope: .global,
        summary: "Thermogenic mechanism by which mitochondria dissipate energy as heat instead of ATP.",
        sections: [
            WikiSection(
                heading: "Definition",
                kind: .definition,
                ordinal: 0,
                claims: [
                    WikiClaim(
                        text: "Uncoupling proteins divert proton gradient energy to heat.",
                        citations: [
                            WikiCitation(
                                episodeID: FixtureID.mitochondriaEpisode,
                                startMS: 1_600_000,
                                endMS: 1_628_000,
                                quoteSnippet: "the proton gradient gets dissipated as heat",
                                speaker: "Andrew Huberman",
                                verificationConfidence: .high
                            )
                        ],
                        confidence: .high
                    )
                ]
            )
        ],
        citations: [
            WikiCitation(
                episodeID: FixtureID.mitochondriaEpisode,
                startMS: 1_600_000,
                endMS: 1_628_000,
                quoteSnippet: "the proton gradient gets dissipated as heat",
                speaker: "Andrew Huberman",
                verificationConfidence: .high
            )
        ],
        confidence: 0.65,
        generatedAt: Date().addingTimeInterval(-3_600 * 32),
        model: "openai/gpt-4o-mini",
        compileRevision: 1
    )

    /// Per-podcast page demonstrating the scoped variant.
    static let hubermanShow: WikiPage = WikiPage(
        slug: "huberman-lab",
        title: "Huberman Lab",
        kind: .show,
        scope: .podcast(FixtureID.hubermanPodcast),
        summary: "Stanford neuroscientist Andrew Huberman's long-form weekly podcast on protocols for sleep, focus, and metabolism.",
        sections: [
            WikiSection(
                heading: "Definition",
                kind: .definition,
                ordinal: 0,
                claims: [
                    WikiClaim(
                        text: "Long-form weekly podcast hosted by Stanford neuroscientist Andrew Huberman covering protocols for sleep, focus, and metabolism.",
                        citations: [],
                        confidence: .high,
                        isGeneralKnowledge: true
                    )
                ]
            )
        ],
        confidence: 0.80,
        model: "openai/gpt-4o-mini"
    )

    // MARK: - All fixtures

    static let all: [WikiPage] = [
        ozempicTopic,
        mitochondriaTopic,
        hubermanShow,
    ]

    /// Inventory derived from the fixture pages — useful when previewing
    /// the wiki home without writing pages to disk first.
    static var inventory: WikiInventory {
        var inventory = WikiInventory()
        for page in all {
            let url = URL(fileURLWithPath: "/dev/null/\(page.slug).json")
            inventory.upsert(.init(from: page, fileURL: url))
        }
        return inventory
    }
}
