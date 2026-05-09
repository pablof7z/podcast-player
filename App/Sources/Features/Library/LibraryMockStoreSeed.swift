import Foundation

// MARK: - LibraryMockStoreSeed

/// Static seed data for `LibraryMockStore`. Split out so the store file
/// stays under the 300-line soft limit and so the seed is easy to scan
/// when reviewing what the lane will look like in screenshots.
///
/// Show names match the canonical examples in `ux-02-library.md` (Tim
/// Ferriss, Lex Fridman, Dwarkesh, Joe Rogan, Acquired) so the mock UI
/// reads as the spec author intended; the rest are realistic adjacent
/// shows in the same category lineage.
enum LibraryMockStoreSeed {

    // MARK: - Public entry points

    /// Builds the full subscriptions + episodes seed. 10 subscriptions,
    /// 30+ episodes total (the lane brief asks for ≥30).
    static func build() -> (subscriptions: [LibraryMockSubscription],
                            episodes: [UUID: [LibraryMockEpisode]]) {
        let subs = makeSubscriptions()
        var byShow: [UUID: [LibraryMockEpisode]] = [:]
        for sub in subs {
            byShow[sub.id] = makeEpisodes(for: sub)
        }
        return (subs, byShow)
    }

    /// One additional subscription for the mock OPML import flow.
    static func makeImported(index: Int) -> LibraryMockSubscription {
        let names: [(String, String, String)] = [
            ("Hard Fork",            "Casey Newton & Kevin Roose", "antenna.radiowaves.left.and.right"),
            ("Conversations with Tyler", "Tyler Cowen",             "graduationcap.fill"),
            ("Founders",             "David Senra",                "books.vertical.fill"),
        ]
        let pick = names[index % names.count]
        return LibraryMockSubscription(
            id: UUID(),
            title: pick.0,
            author: pick.1,
            artworkSymbol: pick.2,
            accentHue: Double((index * 47) % 360) / 360.0,
            episodeCount: 80 + index * 11,
            unplayedCount: index % 3,
            isSubscribed: true,
            wikiReady: false,
            transcriptsEnabled: true,
            showDescription: "Imported via OPML — wiki and transcripts will catch up shortly."
        )
    }

    // MARK: - Subscriptions

    private static func makeSubscriptions() -> [LibraryMockSubscription] {
        [
            sub("The Tim Ferriss Show", "Tim Ferriss",
                "leaf.fill", hue: 0.06,
                episodes: 812, unplayed: 3,
                wiki: true, transcripts: true,
                desc: "Long-form interviews with world-class performers — investors, athletes, writers, founders."),
            sub("Lex Fridman Podcast", "Lex Fridman",
                "atom", hue: 0.62,
                episodes: 458, unplayed: 1,
                wiki: true, transcripts: true,
                desc: "Conversations about science, technology, history, philosophy and the nature of intelligence."),
            sub("Dwarkesh Podcast", "Dwarkesh Patel",
                "books.vertical", hue: 0.72,
                episodes: 94, unplayed: 2,
                wiki: true, transcripts: true,
                desc: "Sharp, prepared interviews with frontier researchers, historians, and economists."),
            sub("Acquired", "Ben Gilbert & David Rosenthal",
                "chart.line.uptrend.xyaxis", hue: 0.04,
                episodes: 198, unplayed: 0,
                wiki: true, transcripts: true,
                desc: "Every episode tells the story of one great company — how it was built, how it scaled, why it endured."),
            sub("Huberman Lab", "Andrew Huberman",
                "brain.head.profile", hue: 0.38,
                episodes: 224, unplayed: 4,
                wiki: false, transcripts: true,
                desc: "Practical, science-grounded tools for sleep, focus, fitness, and emotional regulation."),
            sub("The Joe Rogan Experience", "Joe Rogan",
                "mic.fill", hue: 0.00,
                episodes: 2_104, unplayed: 0,
                wiki: false, transcripts: false,
                desc: "Long, unstructured conversations with comedians, scientists, fighters, and friends."),
            sub("Stratechery", "Ben Thompson",
                "rectangle.stack.fill", hue: 0.55,
                episodes: 312, unplayed: 1,
                wiki: true, transcripts: true,
                desc: "Daily strategy and analysis at the intersection of technology and business."),
            sub("Invest Like the Best", "Patrick O'Shaughnessy",
                "dollarsign.circle.fill", hue: 0.30,
                episodes: 364, unplayed: 0,
                wiki: true, transcripts: true,
                desc: "Conversations with the best investors and operators in the world."),
            sub("Cortex", "Myke Hurley & CGP Grey",
                "brain", hue: 0.78,
                episodes: 156, unplayed: 0,
                wiki: false, transcripts: true,
                desc: "Two professional internet-friends discuss productivity, plans, and the work that makes their work possible."),
            sub("99% Invisible", "Roman Mars",
                "building.columns.fill", hue: 0.13,
                episodes: 587, unplayed: 2,
                wiki: true, transcripts: true,
                desc: "Stories about all the thought that goes into the things we don't think about — design, architecture, the world we built."),
        ]
    }

    private static func sub(_ title: String,
                            _ author: String,
                            _ symbol: String,
                            hue: Double,
                            episodes: Int,
                            unplayed: Int,
                            wiki: Bool,
                            transcripts: Bool,
                            desc: String) -> LibraryMockSubscription {
        LibraryMockSubscription(
            id: UUID(),
            title: title,
            author: author,
            artworkSymbol: symbol,
            accentHue: hue,
            episodeCount: episodes,
            unplayedCount: unplayed,
            isSubscribed: true,
            wikiReady: wiki,
            transcriptsEnabled: transcripts,
            showDescription: desc
        )
    }

    // MARK: - Episodes

    /// Builds 4 episodes per subscription — newest played-with-progress,
    /// next downloaded-and-transcribed, then a mid-transcribe one, then
    /// an older played one. Total = 40 episodes (>30 lane requirement).
    private static func makeEpisodes(for sub: LibraryMockSubscription) -> [LibraryMockEpisode] {
        let baseNumber = sub.episodeCount
        let now = Date()
        let day: TimeInterval = 86_400
        let titles = episodeTitles(for: sub.title)

        return [
            LibraryMockEpisode(
                id: UUID(),
                subscriptionID: sub.id,
                number: baseNumber,
                title: titles[0],
                summary: "A wide-ranging conversation that runs longer than planned and ends in genuine surprise.",
                durationSeconds: 8_070,
                publishedAt: now.addingTimeInterval(-day * 1),
                isPlayed: false,
                playbackProgress: 0.36,
                downloadStatus: .downloaded(transcribed: true)
            ),
            LibraryMockEpisode(
                id: UUID(),
                subscriptionID: sub.id,
                number: baseNumber - 1,
                title: titles[1],
                summary: "On craft, on contrarian bets, and on what only experience can teach you.",
                durationSeconds: 6_420,
                publishedAt: now.addingTimeInterval(-day * 4),
                isPlayed: false,
                playbackProgress: 0.0,
                downloadStatus: .downloading(progress: 0.64)
            ),
            LibraryMockEpisode(
                id: UUID(),
                subscriptionID: sub.id,
                number: baseNumber - 2,
                title: titles[2],
                summary: "A working session about strategy, attention, and the loop between writing and thinking.",
                durationSeconds: 5_280,
                publishedAt: now.addingTimeInterval(-day * 9),
                isPlayed: false,
                playbackProgress: 0.0,
                downloadStatus: .transcribing(progress: 0.42)
            ),
            LibraryMockEpisode(
                id: UUID(),
                subscriptionID: sub.id,
                number: baseNumber - 3,
                title: titles[3],
                summary: "An older favorite — the conversation people keep coming back to and quoting at dinner.",
                durationSeconds: 4_790,
                publishedAt: now.addingTimeInterval(-day * 18),
                isPlayed: true,
                playbackProgress: 1.0,
                downloadStatus: .downloaded(transcribed: true)
            ),
        ]
    }

    /// Per-show episode title bank. Believable, not parodic.
    private static func episodeTitles(for show: String) -> [String] {
        switch show {
        case "The Tim Ferriss Show":
            return ["Keto with Dr. Peter Attia",
                    "Building resilience under pressure",
                    "The art of slow productivity",
                    "Lessons from 20 years of investing"]
        case "Lex Fridman Podcast":
            return ["How AI changes the nature of work",
                    "Consciousness, cosmology, and code",
                    "The mathematics of attention",
                    "Self-driving and the long game"]
        case "Dwarkesh Podcast":
            return ["Gwern on the next decade of compute",
                    "Daniela Rus on robots that reason",
                    "Tyler Cowen on stagnation revisited",
                    "Patrick Collison on what makes a great team"]
        case "Acquired":
            return ["Costco — the inside story",
                    "How Nintendo learned to play the long game",
                    "TSMC, part one",
                    "The Hermès dynasty"]
        case "Huberman Lab":
            return ["Sleep architecture and circadian alignment",
                    "Dopamine, motivation, and the cost of cheap rewards",
                    "Cold exposure protocols, evidence-based",
                    "Stress, breath, and parasympathetic recovery"]
        case "The Joe Rogan Experience":
            return ["Comedy, fights, and what makes a story",
                    "On hunting, conservation, and the outdoors",
                    "Three hours with a working scientist",
                    "An old friend stops by for a long one"]
        case "Stratechery":
            return ["Antitrust, aggregation, and the next regulatory wave",
                    "Apple's quiet strategic shift",
                    "What OpenAI is really building",
                    "The bull case for legacy media"]
        case "Invest Like the Best":
            return ["The compounding power of taste",
                    "How to allocate when nothing is cheap",
                    "Founder-mode versus manager-mode",
                    "What a great LP relationship looks like"]
        case "Cortex":
            return ["Yearly themes, mid-year check-in",
                    "The work that makes the work possible",
                    "On notebooks, again",
                    "Travel productivity is a lie"]
        case "99% Invisible":
            return ["The quiet revolution of bus stops",
                    "Why your sidewalk is the wrong width",
                    "How a font becomes a city",
                    "The architecture of waiting"]
        default:
            return ["Conversation no. 1",
                    "Conversation no. 2",
                    "Conversation no. 3",
                    "Conversation no. 4"]
        }
    }
}
