import Foundation

// TODO: Generates personalised "TLDR of this week's podcasts" audio briefings.
// Composes script via LLM, synthesizes via TTS (ElevenLabs), supports
// interruption + branching (user asks a follow-up, agent answers, returns).

/// Produces synthesized audio briefings from the user's recent listening.
///
/// Intentionally empty at this stage — the synthesized product spec will define
/// scope parameters (timeframe, length, voice), branching policy, and the
/// underlying script-then-synthesize pipeline.
final class BriefingComposer {
    init() {}
}
