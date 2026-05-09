import Foundation

// MARK: - MockEpisode

/// A minimal Episode-shaped struct used while Lane 2's `Podcast/Episode.swift`
/// is still in flight. EpisodeDetail views consume `MockEpisode`; when Lane 2
/// merges, swap the type alias and delete this file.
///
/// Kept deliberately small — title, show, artwork URL, duration, publish
/// date, chapters. Anything richer comes from Lane 2.
struct MockEpisode: Sendable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let showName: String
    let episodeNumber: Int?
    let publishedAt: Date
    let duration: TimeInterval
    let artworkURL: URL?
    let summary: String
    let showNotesHTML: String
    let chapters: [Chapter]

    struct Chapter: Sendable, Hashable, Identifiable {
        let id: UUID
        let start: TimeInterval
        let title: String
    }
}

// MARK: - Fixture

enum MockEpisodeFixture {

    /// A two-speaker fixture (Tim Ferriss + Peter Attia) so the reader view
    /// has speaker switches and a chapter rail to morph against.
    static func timFerrissKeto() -> (MockEpisode, Transcript) {
        let episodeID = UUID()
        let chapters: [MockEpisode.Chapter] = [
            .init(id: UUID(), start: 0, title: "Cold open"),
            .init(id: UUID(), start: 252, title: "Why ketones matter"),
            .init(id: UUID(), start: 1720, title: "The Inuit objection"),
            .init(id: UUID(), start: 4810, title: "Practical protocols")
        ]
        let episode = MockEpisode(
            id: episodeID,
            title: "How to Think About Keto",
            showName: "The Tim Ferriss Show",
            episodeNumber: 732,
            publishedAt: Date(timeIntervalSince1970: 1_714_780_800), // 2024-05-04
            duration: 60 * 60 * 2 + 14 * 60,
            artworkURL: nil,
            summary: "Ferriss and Attia trace the arc of metabolic research from 1920s ketogenic seizure clinics to today's debates about metabolic flexibility — and where the orthodoxy is wrong.",
            showNotesHTML: "<p>This week, Tim sits down with <b>Peter Attia, MD</b> to revisit a topic the show has circled for years: ketones, metabolic flexibility, and what the data actually says.</p><p>Topics covered:</p><ul><li>Ketogenic diets vs cyclic ketosis</li><li>The Inuit study controversy</li><li>Practical protocols for endurance athletes</li></ul>",
            chapters: chapters
        )

        // Build two speakers with stable IDs.
        let tim = Speaker(label: "Tim Ferriss", displayName: "Tim Ferriss")
        let peter = Speaker(label: "Peter Attia", displayName: "Peter Attia")
        let speakers = [tim, peter]

        let segments = sampleSegments(timID: tim.id, peterID: peter.id)
        let transcript = Transcript(
            episodeID: episodeID,
            language: "en-US",
            source: .publisher,
            segments: segments,
            speakers: speakers,
            generatedAt: Date()
        )
        return (episode, transcript)
    }

    /// An "in-progress" Scribe transcript — mostly empty, used to drive the
    /// `TranscribingInProgressView`.
    static func inProgress() -> (MockEpisode, Transcript) {
        let (episode, _) = timFerrissKeto()
        let transcript = Transcript(
            episodeID: episode.id,
            language: "en-US",
            source: .scribeV1,
            segments: [
                Segment(start: 0, end: 4.2, speakerID: nil,
                        text: "Welcome back to the show. Today I'm joined by",
                        words: nil)
            ],
            speakers: [],
            generatedAt: Date()
        )
        return (episode, transcript)
    }

    // MARK: - Internals

    private static func sampleSegments(timID: UUID, peterID: UUID) -> [Segment] {
        var segs: [Segment] = []
        var t: TimeInterval = 0

        func add(_ speakerID: UUID?, _ text: String, length: TimeInterval = 6) {
            segs.append(Segment(start: t, end: t + length, speakerID: speakerID, text: text, words: nil))
            t += length
        }

        // Cold open
        add(nil, "[intro music]", length: 8)
        add(timID, "Welcome back to the show. Today I'm joined by my friend Dr. Peter Attia. Peter, welcome back.")
        add(peterID, "Thanks Tim, great to be here.", length: 4)

        // Skip to chapter 2 region
        t = 252
        add(timID, "So when you talk about metabolic flexibility, what do you actually mean? Like in a clinical sense?")
        add(peterID, "Right, so the term gets thrown around, but really what we're measuring is the body's ability to switch substrate utilization on demand.", length: 10)
        add(peterID, "If you're forced into glycolysis at all times, you've lost a degree of freedom your physiology used to have.", length: 9)
        add(timID, "And that's the part that the popular literature gets wrong, isn't it.", length: 6)
        add(peterID, "Almost universally. People conflate ketosis with metabolic flexibility, and they are not the same thing.", length: 8)

        // Chapter 3 region
        t = 1720
        add(peterID, "There's a classic Inuit study that pushed back on the orthodoxy. People said look, here's a population that's clearly metabolically robust on a near-zero-carb diet.", length: 14)
        add(timID, "And the counter-argument was?", length: 3)
        add(peterID, "That the cohort had a genetic adaptation that made it not generalizable. Which, frankly, I think was the right read.", length: 10)

        return segs
    }
}
