import SwiftUI

/// Static demo data for the player lane.
///
/// Two-speaker conversation, ~40 lines, monotonically increasing timestamps —
/// stand-in for what Lane 5's real transcript stream will provide. Speaker
/// colors come from an art-extracted palette baked into `MockEpisode`; here
/// we use plausible cover-art-friendly tints.
enum MockTranscriptFixture {

    struct Bundle {
        let episode: MockEpisode
        let lines: [MockTranscriptLine]
    }

    static let timFerrissKetoDemo: Bundle = makeKetoDemo()

    // MARK: - Builder

    private static func makeKetoDemo() -> Bundle {
        // Two-speaker palette — Tim warm, Dom cool. These would come from
        // diarization + cover-art extraction in production.
        let timColor = Color(red: 0.91, green: 0.55, blue: 0.30)   // copper-amber (host)
        let domColor = Color(red: 0.36, green: 0.62, blue: 0.78)   // soft azure (guest)

        let episode = MockEpisode(
            id: "tim-ferriss-742",
            showName: "The Tim Ferriss Show",
            episodeNumber: 742,
            title: "The Keto Protocol With Dom D'Agostino",
            chapterTitle: "Chapter 3 · Mitochondrial efficiency",
            duration: 60 * 72 + 4, // 1h 12m 4s — matches the brief wireframe.
            primaryArtColor: Color(red: 0.86, green: 0.45, blue: 0.22), // copper warm
            secondaryArtColor: Color(red: 0.18, green: 0.20, blue: 0.30) // ink cool
        )

        let raw: [(speaker: Speaker, text: String, dur: TimeInterval)] = [
            (.tim, "Welcome back to the show, Dom. It's been a minute.", 4.2),
            (.dom, "Glad to be back, Tim. A lot has changed since we last talked.", 5.1),
            (.tim, "Most people get this wrong, so let's start at the top.", 4.6),
            (.dom, "Right, because the literature is genuinely confusing on this.", 4.8),
            (.tim, "Wait — can you actually define ketosis for the audience?", 4.4),
            (.dom, "Sure. Ketosis is a metabolic state where the body shifts its primary fuel source.", 7.2),
            (.dom, "Specifically, from glucose to fat-derived ketone bodies.", 5.0),
            (.tim, "And how long until adaptation actually kicks in?", 4.0),
            (.dom, "Two to six weeks for most people, depending on baseline.", 4.7),
            (.tim, "When you say \"ketones,\" what do you actually mean at the molecular level?", 5.6),
            (.dom, "I mean beta-hydroxybutyrate — BHB, the dominant circulating ketone.", 5.6),
            (.dom, "Which the brain prefers over glucose under prolonged fasting.", 5.0),
            (.tim, "And there's an evolutionary argument for that, right?", 4.0),
            (.dom, "Absolutely. Fat is the body's strategic reserve. Ketones are how we stay sharp during scarcity.", 7.4),
            (.tim, "Talk to me about the cognitive piece. People feel different on keto.", 5.2),
            (.dom, "Cleaner energy curve, fewer glucose crashes, generally calmer focus.", 5.4),
            (.dom, "But the first two weeks can feel rough — the so-called keto flu.", 5.0),
            (.tim, "What's actually happening physiologically during that adjustment?", 5.0),
            (.dom, "Electrolyte depletion mostly. Sodium drops fast as insulin falls.", 5.2),
            (.dom, "So we tell people: salt your food, magnesium at night, plenty of potassium.", 5.6),
            (.tim, "Practical. Let's talk about endurance athletes — does this hold up under load?", 5.6),
            (.dom, "It does, but the protocol is different. Cyclical or targeted approaches usually win.", 6.0),
            (.tim, "Define that for me. I want listeners to be able to act on this.", 5.2),
            (.dom, "Cyclical means you carb-load on training days. Targeted means right around workouts.", 6.4),
            (.tim, "And mitochondrial efficiency — that was your work at USF, right?", 5.4),
            (.dom, "Right. We saw measurable density improvements after eight weeks of strict adaptation.", 6.6),
            (.tim, "Talk to me about therapeutic ketosis. This is where it gets interesting.", 5.4),
            (.dom, "Glioblastoma. Drug-resistant epilepsy. Anywhere mitochondrial dysfunction is upstream.", 6.4),
            (.tim, "And exogenous ketones — the supplements — where do they fit?", 5.2),
            (.dom, "Good for transition support. Not a substitute for adaptation. Tool, not solution.", 5.8),
            (.tim, "What does a typical day look like for you, food-wise?", 4.8),
            (.dom, "Eggs, avocado, olive oil, sardines. Coffee with MCT. Boring on purpose.", 6.0),
            (.tim, "Boring is the secret. Most of my best decisions were boring.", 4.6),
            (.dom, "Same. Optimization comes from removing variables, not adding them.", 5.4),
            (.tim, "Final question: who in the field do you think is doing the most underrated work?", 5.8),
            (.dom, "Stephen Phinney. Volek. The early researchers who built the foundations.", 5.4),
            (.tim, "Where can people find your latest research?", 4.0),
            (.dom, "ketonutrition.org and on PubMed under D'Agostino DP.", 5.0),
            (.tim, "Dom, thanks for coming back. This was excellent.", 4.0),
            (.dom, "Always a pleasure, Tim.", 2.4),
        ]

        var lines: [MockTranscriptLine] = []
        var cursor: TimeInterval = 60 * 24 + 18 // start at 24:18 to match brief.
        for (idx, entry) in raw.enumerated() {
            let line = MockTranscriptLine(
                id: idx,
                speakerID: entry.speaker.rawValue,
                speakerName: entry.speaker.displayName,
                speakerColor: entry.speaker == .tim ? timColor : domColor,
                text: entry.text,
                start: cursor,
                end: cursor + entry.dur
            )
            lines.append(line)
            // ~120ms breath between lines so the active-line transition has air.
            cursor = line.end + 0.12
        }

        return Bundle(episode: episode, lines: lines)
    }

    private enum Speaker: String {
        case tim, dom
        var displayName: String {
            switch self {
            case .tim: return "TIM"
            case .dom: return "DOM"
            }
        }
    }
}
