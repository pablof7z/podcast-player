import Foundation

// MARK: - PlaybackRate

/// Playback rates surfaced in the speed sheet. Stored as `Double` so the value
/// maps directly onto `AVPlayer.rate` via the audio engine.
///
/// Preset set is wider than the original 5 rates — power podcast listeners
/// commonly run at 1.7× / 2× / 2.5×, and the +0.1 increments (1.1, 1.3) are
/// the most-tapped "just slightly faster" values across Apple Podcasts /
/// Pocket Casts / Overcast user research. Apple's player surfaces 0.5–3.0
/// in 0.1 steps; we ship the most-common 10 of those rather than 26 rows.
enum PlaybackRate: Double, CaseIterable, Identifiable {
    case slowest = 0.5
    case slow = 0.8
    case normal = 1.0
    case slightlyFast = 1.1
    case quick = 1.2
    case quicker = 1.3
    case fast = 1.5
    case fasterStill = 1.7
    case fastest = 2.0
    case turbo = 2.5
    case max = 3.0

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .normal: return "1×"
        default:      return String(format: "%g×", rawValue)
        }
    }

    /// Best-fit rate for an arbitrary engine rate (e.g. restored from a per-show
    /// override). Falls back to `.normal` when nothing is reasonably close.
    static func bestFit(for rate: Double) -> PlaybackRate {
        allCases.min(by: { abs($0.rawValue - rate) < abs($1.rawValue - rate) }) ?? .normal
    }
}

// MARK: - PlaybackSleepTimer

/// Sleep-timer presets surfaced in the sleep-timer sheet. Mapped onto the
/// engine's `SleepTimer.Mode` at the boundary.
enum PlaybackSleepTimer: Hashable, Identifiable {
    case off
    case minutes(Int)
    case endOfEpisode

    var id: String {
        switch self {
        case .off: return "off"
        case .minutes(let m): return "m\(m)"
        case .endOfEpisode: return "eoe"
        }
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .minutes(let m): return "\(m) min"
        case .endOfEpisode: return "End of episode"
        }
    }

    static let presets: [PlaybackSleepTimer] = [
        .off, .minutes(5), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfEpisode
    ]

    var engineMode: SleepTimer.Mode {
        switch self {
        case .off: return .off
        case .minutes(let m): return .duration(TimeInterval(m * 60))
        case .endOfEpisode: return .endOfEpisode
        }
    }
}
