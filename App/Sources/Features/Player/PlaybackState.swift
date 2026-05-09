import Foundation
import Observation
import SwiftUI

// MARK: - PlaybackRate

/// Playback rates surfaced in the speed sheet. Stored as `Double` so the value
/// maps directly onto `AVPlayer.rate` via the audio engine.
enum PlaybackRate: Double, CaseIterable, Identifiable {
    case slow = 0.8
    case normal = 1.0
    case quick = 1.2
    case fast = 1.5
    case fastest = 2.0

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .normal: return "1×"
        default:      return String(format: "%.1f×", rawValue)
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

// MARK: - PlaybackState

/// Real, observable wrapper around `AudioEngine` that the Player UI binds to.
///
/// Owns a single `AudioEngine` instance and republishes its state through
/// `@Observable` properties so SwiftUI re-renders on changes. The wrapper also:
///   - Throttles a 1-second progress mirror back into `AppStateStore` for
///     persistence (prevents 30 writes/second flood through `state.didSet`).
///   - Detects end-of-episode and marks the episode played in the store.
///   - Adapts the engine's `SleepTimer.Mode` to the UI's preset enum.
///
/// Persistence is wired via closures (`onPersistPosition`, `onEpisodeFinished`)
/// rather than holding an `AppStateStore` reference directly — it keeps this
/// type testable in isolation and side-steps the `@State` init-order problem
/// where `RootView` cannot read `@Environment` during property initialization.
@MainActor
@Observable
final class PlaybackState {

    // MARK: - Engine

    /// The single `AVPlayer`-backed engine. Held here so SwiftUI views can also
    /// reach into `engine.sleepTimer.phase` for countdown rendering.
    let engine: AudioEngine

    // MARK: - Observable surface (matches the binding contract the UI expects)

    /// Currently-loaded episode, or `nil` when nothing has been queued.
    /// The `RootView` mini-bar reads this to decide whether to render itself.
    var episode: Episode?

    var isAirPlayActive: Bool = false

    var sleepTimer: PlaybackSleepTimer = .off

    /// Mirrors `AudioEngine.state` semantics through the lens the UI cares
    /// about: `playing` and `buffering` both render as "playing" so the
    /// play/pause glyph doesn't flicker through transient stalls.
    var isPlaying: Bool {
        switch engine.state {
        case .playing, .buffering: return true
        case .idle, .loading, .paused, .failed: return false
        }
    }

    /// Engine playhead, in seconds.
    var currentTime: TimeInterval { engine.currentTime }

    /// Engine duration. Falls back to the feed-supplied `Episode.duration` so
    /// the scrubber renders a sane width before `AVAsset` resolves the asset
    /// duration.
    var duration: TimeInterval {
        if engine.duration > 0 { return engine.duration }
        return episode?.duration ?? 0
    }

    /// Best-fit `PlaybackRate` for the engine's current rate. Reads always go
    /// through `engine.rate` so a remote `MPRemoteCommand` rate change still
    /// updates the UI.
    var rate: PlaybackRate {
        get { PlaybackRate.bestFit(for: engine.rate) }
        set { engine.setRate(newValue.rawValue) }
    }

    // MARK: - Persistence hooks (wired by RootView at .onAppear time)

    /// Called once per second while playback advances. Receivers should
    /// persist the playhead so the user resumes where they left off across
    /// app launches.
    var onPersistPosition: (UUID, TimeInterval) -> Void = { _, _ in }

    /// Called once per episode when the playhead reaches the end. Receivers
    /// should mark the episode as fully played.
    var onEpisodeFinished: (UUID) -> Void = { _ in }

    // MARK: - Internal

    /// Drives the 1-second persistence + end-detection loop.
    private var persistenceTask: Task<Void, Never>?
    /// Prevents `onEpisodeFinished` from firing twice for the same playthrough.
    private var didFireFinishedFor: UUID?

    // MARK: - Init

    init(engine: AudioEngine = AudioEngine()) {
        self.engine = engine
    }

    // MARK: - Episode lifecycle

    /// Replace the current item with `newEpisode`. Resumes from the persisted
    /// `playbackPosition` when present. Caller must follow with `play()` to
    /// actually start audio — matches the engine's deliberate two-step flow.
    func setEpisode(_ newEpisode: Episode) {
        if episode?.id != newEpisode.id {
            didFireFinishedFor = nil
        }
        episode = newEpisode
        engine.load(newEpisode)
        if newEpisode.playbackPosition > 0 {
            engine.seek(to: newEpisode.playbackPosition)
        }
        startPersistenceLoop()
    }

    // MARK: - Imperative methods (binding contract for the player UI)

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard episode != nil else { return }
        Haptics.medium()
        engine.play()
        startPersistenceLoop()
    }

    func pause() {
        Haptics.soft()
        engine.pause()
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
        Haptics.selection()
    }

    /// `seekSnapping` was a transcript-snap behaviour in the mock. With the
    /// transcript stubbed (lane-3 pending) it now just delegates to `seek`.
    func seekSnapping(to time: TimeInterval) {
        seek(to: time)
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        engine.skip(back: seconds)
    }

    func skipForward(_ seconds: TimeInterval = 30) {
        engine.skip(forward: seconds)
    }

    func setRate(_ newRate: PlaybackRate) {
        engine.setRate(newRate.rawValue)
        Haptics.selection()
    }

    func setSleepTimer(_ timer: PlaybackSleepTimer) {
        sleepTimer = timer
        engine.setSleepTimer(timer.engineMode)
        Haptics.selection()
    }

    // MARK: - Persistence loop

    /// Polls `engine.currentTime` once per second and forwards to the persistence
    /// closure. A separate path detects end-of-episode so the store can flip
    /// `played = true` without subscribing to the engine's internal observer.
    private func startPersistenceLoop() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tickPersistence()
            }
        }
    }

    private func tickPersistence() {
        guard let episode else { return }
        // Once the episode is marked finished, stop touching its position —
        // otherwise we'd persist `currentTime == duration` right back over the
        // store-side reset that `markEpisodePlayed` performed.
        guard didFireFinishedFor != episode.id else { return }

        let time = engine.currentTime
        if time > 0 {
            onPersistPosition(episode.id, time)
        }

        // Natural end-of-item handler in `AudioEngine+Observers` pins
        // `currentTime` to exactly `duration`. A 0.1s tolerance absorbs any
        // observer jitter without misclassifying a manual pause near the end.
        let total = duration
        if total > 0, time >= total - 0.1, !isPlaying {
            didFireFinishedFor = episode.id
            onEpisodeFinished(episode.id)
        }
    }
}
