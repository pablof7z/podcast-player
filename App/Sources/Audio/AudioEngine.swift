import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os.log

// MARK: - EngineError

/// `Error`-conforming + `Equatable` so the engine's `State` enum can stay
/// `Equatable` for SwiftUI diffing.
struct EngineError: Error, Equatable, Sendable, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - AudioEngine

/// Wraps a single `AVPlayer`, exposes an `@Observable` playback state, and
/// brokers commands from the player UI, the agent, and Now Playing controls.
///
/// Owns:
/// - The active `AVPlayer` and its `AVPlayerItem`
/// - `AudioSessionCoordinator` activation for `.podcastPlayback`
/// - A `NowPlayingCenter` instance (lock-screen + Control Center bridge)
/// - A `SleepTimer` (duration / end-of-episode / fade-out)
///
/// Lifecycle: `idle → loading(Episode) → playing | paused → buffering → playing`,
/// with `failed(EngineError)` reachable from any state. Observer wiring lives
/// in `AudioEngine+Observers.swift` to stay under the 300-line soft limit.
@MainActor
@Observable
final class AudioEngine {

    // MARK: - State

    enum State: Equatable, Sendable {
        case idle
        case loading(Episode)
        case playing
        case paused
        case buffering
        case failed(EngineError)
    }

    // MARK: - Observable surface

    private(set) var state: State = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Double = 1.0
    private(set) var episode: Episode?

    /// Sleep-timer surface so the player UI can render the countdown.
    let sleepTimer = SleepTimer()

    /// NowPlaying surface — exposed so the player can push artwork mid-playback
    /// once Lane 4 has it loaded (artwork isn't on `Episode` yet — Lane 2 owns).
    let nowPlaying = NowPlayingCenter()

    // MARK: - Tunables

    /// Asymmetric defaults — see baseline-podcast-features.md (forward 30s, back 15s).
    var skipForwardSeconds: Double = 30 {
        didSet { nowPlaying.setSkipIntervals(forward: skipForwardSeconds, backward: skipBackwardSeconds) }
    }
    var skipBackwardSeconds: Double = 15 {
        didSet { nowPlaying.setSkipIntervals(forward: skipForwardSeconds, backward: skipBackwardSeconds) }
    }

    // MARK: - Now Playing metadata resolvers
    //
    // Closures injected by `RootView` so the lock-screen / Control Center
    // metadata can show the show name and active chapter title without
    // coupling the engine to `AppStateStore`. Each defaults to a no-op so
    // the engine works in isolation (unit tests, previews).

    /// Returns the show (subscription) title for an episode. Surfaces as the
    /// lock-screen `MPMediaItemPropertyArtist` line.
    var resolveShowName: (Episode) -> String? = { _ in nil }

    /// Returns the active chapter title at `playhead`, when the live episode
    /// has navigable chapters. Surfaces as the lock-screen
    /// `MPMediaItemPropertyAlbumTitle` line. Pass-through closure so the
    /// engine doesn't have to know how chapters are stored.
    var resolveActiveChapterTitle: (Episode, TimeInterval) -> String? = { _, _ in nil }

    /// Most-recently-published chapter title — checked on each time-observer
    /// tick so a chapter boundary crossing triggers a full nowPlaying republish
    /// (the lightweight `updateElapsed` path only refreshes elapsed/rate).
    var lastPublishedChapterTitle: String?

    // MARK: - Internal (shared with AudioEngine+Observers.swift)

    let logger = Logger.app("AudioEngine")
    let player = AVPlayer()
    var timeObserverToken: Any?
    var statusObservation: NSKeyValueObservation?
    var timeControlObservation: NSKeyValueObservation?
    var bufferEmptyObservation: NSKeyValueObservation?
    var bufferLikelyToKeepUpObservation: NSKeyValueObservation?
    var endObserver: NSObjectProtocol?
    var fadeBaseVolume: Float = 1.0

    // MARK: - Init / deinit

    init() {
        configureNowPlayingCallbacks()
        configureSleepTimerHooks()
        nowPlaying.setSkipIntervals(forward: skipForwardSeconds, backward: skipBackwardSeconds)
    }

    // Note: no `deinit` cleanup. Under Swift 6 strict concurrency, `deinit` is
    // nonisolated and cannot touch `@MainActor` properties. `AVPlayer` releases
    // its time observer on deallocation; the `NotificationCenter` token also
    // dies with the engine. Explicit teardown happens in `teardownItemObservers()`
    // when a new episode loads.

    // MARK: - Public API

    /// Replace the current item with `episode`. Begins buffering immediately;
    /// caller must follow with `play()` to start playback.
    ///
    /// Prefers the locally-downloaded enclosure when available. We recompute
    /// the local path from `EpisodeDownloadStore` (rather than trusting the
    /// `localFileURL` baked into `DownloadState.downloaded`) because iOS may
    /// rotate the app container path across launches, leaving the persisted
    /// absolute URL stale. Falls back to streaming when no local file exists.
    func load(_ episode: Episode) {
        let url: URL = {
            if EpisodeDownloadStore.shared.exists(for: episode) {
                return EpisodeDownloadStore.shared.localFileURL(for: episode)
            }
            return episode.enclosureURL
        }()
        teardownItemObservers()
        self.episode = episode
        state = .loading(episode)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        installItemObservers(for: item)
        installTimeObserver()

        // Best-effort known-duration fast-path from the feed.
        if let dur = episode.duration {
            duration = dur
        }
        publishNowPlaying()
    }

    /// Start playback. Activates the audio session lazily on first play so the
    /// app doesn't preempt other audio at launch.
    func play() {
        guard episode != nil else { return }
        do {
            try AudioSessionCoordinator.shared.activate(.podcastPlayback)
        } catch {
            logger.error("Failed to activate audio session: \(error, privacy: .public)")
            state = .failed(EngineError("Could not activate audio session: \(error.localizedDescription)"))
            return
        }
        // Restore base volume in case a fade was active.
        player.volume = fadeBaseVolume
        player.playImmediately(atRate: Float(rate))
        if state != .buffering { state = .playing }
        publishNowPlaying()
    }

    /// Pause without releasing the audio session — quicker resume.
    func pause() {
        player.pause()
        state = .paused
        publishNowPlaying()
    }

    func toggle() {
        switch state {
        case .playing, .buffering: pause()
        case .paused, .idle: play()
        case .loading, .failed: break
        }
    }

    /// Seek to absolute position in seconds.
    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = target
                self?.publishNowPlayingElapsed()
            }
        }
    }

    /// Skip forward by `skipForwardSeconds` (default 30).
    func skip(forward seconds: TimeInterval? = nil) {
        seek(to: currentTime + (seconds ?? skipForwardSeconds))
    }

    /// Skip backward by `skipBackwardSeconds` (default 15).
    func skip(back seconds: TimeInterval? = nil) {
        seek(to: currentTime - (seconds ?? skipBackwardSeconds))
    }

    /// Variable-speed playback. 0.5–3.0 per baseline spec; clamped here.
    func setRate(_ newRate: Double) {
        let clamped = min(max(newRate, 0.5), 3.0)
        rate = clamped
        if player.timeControlStatus == .playing {
            player.rate = Float(clamped)
        }
        publishNowPlaying()
    }

    /// Arm a sleep-timer mode. See `SleepTimer.Mode`.
    func setSleepTimer(_ mode: SleepTimer.Mode) {
        sleepTimer.set(mode)
    }

    // MARK: - Now Playing wiring

    private func configureNowPlayingCallbacks() {
        var cb = NowPlayingCenter.Callbacks()
        cb.play   = { [weak self] in self?.play() }
        cb.pause  = { [weak self] in self?.pause() }
        cb.toggle = { [weak self] in self?.toggle() }
        cb.skipForward  = { [weak self] in self?.skip(forward: nil) }
        cb.skipBackward = { [weak self] in self?.skip(back: nil) }
        cb.seek         = { [weak self] t in self?.seek(to: t) }
        cb.changeRate   = { [weak self] r in self?.setRate(r) }
        nowPlaying.setCallbacks(cb)
    }

    private func configureSleepTimerHooks() {
        sleepTimer.onFadeTick = { [weak self] multiplier in
            guard let self else { return }
            self.player.volume = self.fadeBaseVolume * multiplier
        }
        sleepTimer.onFire = { [weak self] in
            self?.pause()
            self?.player.volume = self?.fadeBaseVolume ?? 1.0
        }
    }

    // MARK: - Internal Now Playing helpers (used from +Observers extension)

    func publishNowPlaying() {
        let chapterTitle = episode.flatMap { resolveActiveChapterTitle($0, currentTime) }
        nowPlaying.update(
            title: episode?.title,
            artist: episode.flatMap { resolveShowName($0) },
            albumTitle: chapterTitle,
            duration: duration > 0 ? duration : nil,
            elapsed: currentTime,
            rate: state == .playing ? rate : 0
        )
        lastPublishedChapterTitle = chapterTitle
    }

    func publishNowPlayingElapsed() {
        nowPlaying.updateElapsed(currentTime, rate: state == .playing ? rate : 0)
    }

    // MARK: - State setter (used from +Observers extension)

    /// Exposed for the observer extension; internal so call-sites stay tidy.
    func setState(_ newState: State) {
        self.state = newState
    }

    func setDuration(_ newDuration: TimeInterval) {
        self.duration = newDuration
    }

    func setCurrentTime(_ newTime: TimeInterval) {
        self.currentTime = newTime
    }
}
