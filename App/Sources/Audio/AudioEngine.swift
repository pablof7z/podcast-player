import Foundation

// TODO: Wrap `AVPlayer` (or `AVAudioEngine` if we need DSP) to drive episode
// playback, lock-screen / Now Playing controls, AirPlay, CarPlay, and the
// agent's `play_episode_at(episode_id, timestamp)` tool.

/// Owns the active `AVPlayer`, exposes a `@Observable` playback state, and
/// brokers commands from the player UI, the agent, and Now Playing.
///
/// Intentionally empty at this stage — the synthesized product spec will define
/// the public surface (play/pause, seek, rate, queue, sleep timer, etc.).
final class AudioEngine {
    init() {}
}
