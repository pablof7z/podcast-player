import Foundation

// TODO: Drives push-to-talk and ambient voice conversations with the agent.
// Owns mic capture, STT streaming, agent turn-taking, TTS playback, and
// barge-in (user can interrupt the agent's response mid-utterance).

/// Coordinates speech-in / speech-out conversation flow with the agent.
///
/// Intentionally empty at this stage — the synthesized product spec will define
/// the state machine (idle → listening → thinking → speaking → barge-in).
final class AudioConversationManager {
    init() {}
}
