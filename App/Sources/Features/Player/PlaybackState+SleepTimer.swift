import Foundation

// MARK: - Sleep timer

extension PlaybackState {

    /// Live label for the sleep-timer action chip. Renders the live countdown
    /// when armed in duration mode so the chip reads "29:42" and ticks down
    /// — was previously stuck on the static preset string ("30 min") for the
    /// entire armed window. Read from a SwiftUI view body so @Observable
    /// dependency tracking picks up the engine's per-tick phase changes.
    var sleepTimerChipLabel: String {
        switch engine.sleepTimer.phase {
        case .idle:
            return "Sleep"
        case .armed(let remaining), .fading(let remaining):
            return Self.formatRemaining(remaining)
        case .armedEndOfEpisode:
            return "End"
        case .fired:
            return "Sleep"
        }
    }

    /// `mm:ss` for under an hour, `h:mm:ss` otherwise. Negative / zero values
    /// floor to "0:00" so a brief race during the fade-to-fire transition
    /// doesn't print "-1".
    private static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    func setSleepTimer(_ timer: PlaybackSleepTimer) {
        sleepTimer = timer
        engine.setSleepTimer(timer.engineMode)
        Haptics.selection()
    }
}
