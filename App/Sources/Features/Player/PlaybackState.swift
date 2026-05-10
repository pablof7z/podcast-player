import Foundation
import Observation
import SwiftUI
import WidgetKit

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
/// `@Observable` properties so SwiftUI re-renders on changes. Also: throttles
/// a 1-second persistence mirror, detects end-of-episode, and adapts the
/// engine's `SleepTimer.Mode` to the UI's preset enum. Persistence wires via
/// closures (`onPersistPosition`, `onEpisodeFinished`) so the type stays
/// testable without holding an `AppStateStore` reference directly.
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

    var sleepTimer: PlaybackSleepTimer = .off

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

    /// Up Next queue. Stores `Episode.id`s in playback order — the first entry
    /// is the next episode to play. Kept as `UUID` (not `Episode`) so the
    /// queue stays in sync with mutations against the store (rename, refresh,
    /// download lifecycle) without manual reconciliation.
    ///
    /// `NowPlayingTimelineProvider` reads only the current `episode` snapshot,
    /// not the queue, so widget metadata is unaffected by queue mutations.
    var queue: [UUID] = []

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
    /// should mark the episode as fully played. Gated by `autoMarkPlayedOnFinish`
    /// (mirrors `Settings.autoMarkPlayedAtEnd`) so the user can opt out of auto-mark.
    var onEpisodeFinished: (UUID) -> Void = { _ in }

    /// Called when the player wants any queued position writes drained to
    /// disk synchronously: on pause, on natural end-of-episode (so the
    /// final position survives even when auto-mark-played is off), and on
    /// episode change (so the previous episode's position is durable
    /// before the next episode steals the persistence loop).
    ///
    /// Wired by `RootView` to `AppStateStore.flushPendingPositions`. The
    /// store also flushes on `UIApplication.didEnterBackgroundNotification`
    /// independently, so this closure is for the in-app transitions the
    /// store can't observe directly.
    var onFlushPositions: () -> Void = { }

    /// Mirrors `Settings.autoMarkPlayedAtEnd`. When `false`, end-of-item
    /// detection still stops the persistence loop from over-writing the
    /// final position but skips the `onEpisodeFinished` callback.
    var autoMarkPlayedOnFinish: Bool = true

    /// Resolves the parent show name for a given episode. Called by the
    /// snapshot writer so the widget can render the show subtitle without
    /// `PlaybackState` needing to know about `AppStateStore`. Returns `""`
    /// when the show name isn't known.
    var resolveShowName: (Episode) -> String = { _ in "" }

    /// Resolves the parent show's cover-art URL for a given episode. Used by
    /// the player UI as the fallback when `episode.imageURL` is `nil`.
    /// Mirrors the `resolveShowName` injection pattern so `PlaybackState`
    /// stays decoupled from `AppStateStore`. Returns `nil` when the show's
    /// artwork isn't known.
    var resolveShowImage: (Episode) -> URL? = { _ in nil }

    // MARK: - Internal

    /// Drives the 1-second persistence + end-detection loop.
    private var persistenceTask: Task<Void, Never>?
    /// Prevents `onEpisodeFinished` from firing twice for the same playthrough.
    private var didFireFinishedFor: UUID?
    /// Most recent App-Group snapshot write. Used to throttle position-only
    /// updates to once every 5 seconds — the widget's timeline refresh
    /// granularity makes finer writes wasted I/O.
    private var lastSnapshotWrite: Date?

    // MARK: - Init

    init(engine: AudioEngine = AudioEngine()) {
        self.engine = engine
    }

    // MARK: - Episode lifecycle

    /// Replace the current item with `newEpisode`. Resumes from the persisted
    /// `playbackPosition` when present. Caller must follow with `play()` to
    /// actually start audio — matches the engine's deliberate two-step flow.
    ///
    /// **Idempotent.** When `newEpisode.id` matches the currently-loaded
    /// episode, skip the `engine.load` reload — it would replace the
    /// `AVPlayerItem` and interrupt in-flight playback for a caller that
    /// just wanted "make sure this is loaded" semantics (the EpisodeDetail
    /// hero "Play/Resume" button, chapter-row taps, deep-links). The
    /// metadata refresh + snapshot write still run so any post-hydrate
    /// changes (chapters, title) flush to the widget.
    func setEpisode(_ newEpisode: Episode) {
        let isSameEpisode = (episode?.id == newEpisode.id)
        if !isSameEpisode {
            // Drain any cached position for the previous episode before
            // we steal the persistence loop — otherwise the outgoing
            // playhead would only land on disk at the next 30s eager-cap
            // tick, by which time the user may have force-quit.
            onFlushPositions()
            didFireFinishedFor = nil
            lastSnapshotWrite = nil
        }
        episode = newEpisode
        if !isSameEpisode {
            engine.load(newEpisode)
            if newEpisode.playbackPosition > 0 {
                engine.seek(to: newEpisode.playbackPosition)
            }
        }
        // Episode change is the one event that always justifies a snapshot
        // write — title and artwork just changed, so the widget would
        // otherwise show stale metadata until the next 5-second tick. For
        // same-episode calls we still want the refresh in case chapter
        // hydration or feed-refresh updated the metadata while playback
        // was rolling.
        writeNowPlayingSnapshot(force: true)
        if !isSameEpisode {
            startPersistenceLoop()
        }
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
        // Pause is a "the user is done for now" signal — drain the
        // position cache so the playhead survives a force-quit-after-
        // pause cycle. Cheap when the cache is empty.
        onFlushPositions()
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
        Haptics.selection()
        persistAndFlushAfterUserSeek()
    }

    /// `seekSnapping` was a transcript-snap behaviour in the mock. With the
    /// transcript stubbed (lane-3 pending) it now just delegates to `seek`.
    func seekSnapping(to time: TimeInterval) {
        seek(to: time)
    }

    /// Skip backwards. Pass `nil` (the default) to honour the user's configured
    /// `skipBackwardSeconds` from `Settings`. Pass an explicit value when a UI
    /// gesture wants a specific delta (e.g. transcript chapter rewind).
    func skipBackward(_ seconds: TimeInterval? = nil) {
        engine.skip(back: seconds)
        persistAndFlushAfterUserSeek()
    }

    /// Skip forward. Pass `nil` (the default) to honour the user's configured
    /// `skipForwardSeconds` from `Settings`.
    func skipForward(_ seconds: TimeInterval? = nil) {
        engine.skip(forward: seconds)
        persistAndFlushAfterUserSeek()
    }

    /// Persists the post-seek position immediately and drains the cache.
    ///
    /// Without this, a user who scrubs / skips and then force-quits within
    /// the 30s position-debounce window resumes from the **pre-seek**
    /// position — the engine moved the playhead but the cache hadn't been
    /// touched yet (`tickPersistence` runs on a 1s timer). A user-initiated
    /// position change is the most explicit "remember where I am" signal we
    /// get; treat it like pause and flush eagerly.
    private func persistAndFlushAfterUserSeek() {
        guard let episode else { return }
        let time = engine.currentTime
        if time > 0 {
            onPersistPosition(episode.id, time)
        }
        onFlushPositions()
    }

    // MARK: - Chapter navigation

    /// Jump to the next chapter's `startTime` in the supplied list. No-op
    /// when there is no next chapter (we're already in the last one).
    /// `navigable` is passed in by the UI so it stays in sync with whatever
    /// the live store reports (chapters can hydrate after playback starts —
    /// see `ChaptersHydrationService`).
    func seekToNextChapter(in navigable: [Episode.Chapter]) {
        guard let next = Self.nextChapter(after: currentTime, in: navigable) else { return }
        engine.seek(to: next.startTime)
        Haptics.selection()
        persistAndFlushAfterUserSeek()
    }

    /// Jump to the previous chapter's `startTime`, applying the iOS Music
    /// pattern: if the current chapter started more than
    /// `previousChapterRestartThreshold` seconds ago, restart the current
    /// chapter instead of going further back. This matches the user's
    /// muscle memory for "previous track."
    func seekToPreviousChapter(in navigable: [Episode.Chapter]) {
        guard let target = Self.previousChapter(
            from: currentTime,
            in: navigable,
            restartThreshold: Self.previousChapterRestartThreshold
        ) else { return }
        engine.seek(to: target.startTime)
        Haptics.selection()
        persistAndFlushAfterUserSeek()
    }

    /// Above this many seconds into the current chapter, "previous chapter"
    /// restarts the current chapter instead of stepping back one.
    static let previousChapterRestartThreshold: TimeInterval = 3.0

    /// Pure helper: chapter strictly after `playhead`, or nil when there
    /// isn't one. Exposed as `static nonisolated` so tests can drive it
    /// without spinning up the audio engine and without inheriting
    /// `PlaybackState`'s `@MainActor` isolation.
    nonisolated static func nextChapter(after playhead: TimeInterval, in chapters: [Episode.Chapter]) -> Episode.Chapter? {
        chapters.first(where: { $0.startTime > playhead })
    }

    /// Pure helper: chapter to seek to when the user requests "previous."
    /// Returns the current chapter (restart) when `playhead` is more than
    /// `restartThreshold` seconds into it; otherwise the chapter strictly
    /// before. Returns the first chapter when there is no earlier one.
    nonisolated static func previousChapter(
        from playhead: TimeInterval,
        in chapters: [Episode.Chapter],
        restartThreshold: TimeInterval
    ) -> Episode.Chapter? {
        guard let current = chapters.active(at: playhead) else { return nil }
        let elapsed = playhead - current.startTime
        if elapsed > restartThreshold {
            return current
        }
        // Step back one — find the chapter immediately before `current`.
        guard let idx = chapters.firstIndex(where: { $0.id == current.id }), idx > 0 else {
            return current
        }
        return chapters[idx - 1]
    }

    func setRate(_ newRate: PlaybackRate) {
        engine.setRate(newRate.rawValue)
        Haptics.selection()
    }

    /// Effective skip intervals (read from the engine so the lock-screen and
    /// in-app transport always agree). Surfaced for the player UI to render
    /// the right `gobackward.NN` / `goforward.NN` glyph and the matching
    /// accessibility label.
    var skipForwardSeconds: Int { Int(engine.skipForwardSeconds) }
    var skipBackwardSeconds: Int { Int(engine.skipBackwardSeconds) }

    /// Push live `Settings` values into the engine. Called by `RootView` on
    /// `.onAppear` and again whenever `state.settings` changes so a Settings
    /// edit takes effect immediately on the lock-screen and the in-app transport.
    func applyPreferences(from settings: Settings) {
        engine.skipForwardSeconds = Double(max(1, settings.skipForwardSeconds))
        engine.skipBackwardSeconds = Double(max(1, settings.skipBackwardSeconds))
        // Default rate only takes effect for items that haven't been started.
        // Once the user nudges the speed sheet we don't want to clobber their
        // choice on every settings change, so we only reset when the engine is
        // still at its baseline rate.
        if engine.episode == nil {
            engine.setRate(settings.defaultPlaybackRate)
        }
    }

    func setSleepTimer(_ timer: PlaybackSleepTimer) {
        sleepTimer = timer
        engine.setSleepTimer(timer.engineMode)
        Haptics.selection()
    }

    // MARK: - Queue (Up Next)

    /// Append an episode to the end of the Up Next queue. No-op if the
    /// episode is already queued or is the currently-playing episode — the
    /// queue is intentionally a set-by-identity to avoid the user accidentally
    /// stacking the same episode three times.
    func enqueue(_ episodeID: UUID) {
        guard episodeID != episode?.id else { return }
        guard !queue.contains(episodeID) else { return }
        queue.append(episodeID)
    }

    /// Remove an episode from the Up Next queue. Idempotent.
    func removeFromQueue(_ episodeID: UUID) {
        queue.removeAll { $0 == episodeID }
    }

    /// Move queue entries (List `.onMove` compatible). `source` indices are in
    /// the pre-move array; `destination` is the insertion point in the
    /// post-removal array — matches `Array.move(fromOffsets:toOffset:)`.
    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    /// Clear the entire Up Next queue. Used by the queue sheet's destructive
    /// "Clear queue" footer action.
    func clearQueue() {
        queue.removeAll()
    }

    /// Pop the head of the queue and start playing it. Returns `true` when an
    /// episode was actually played, `false` when the queue is empty or the
    /// resolver couldn't materialise the head episode (e.g. it was deleted
    /// from the store between enqueue and dequeue).
    ///
    /// Takes a `resolve` closure rather than holding an `AppStateStore`
    /// reference directly so `PlaybackState` stays unit-testable. Callers in
    /// the UI pass `{ store.episode(id: $0) }`.
    @discardableResult
    func playNext(resolve: (UUID) -> Episode?) -> Bool {
        guard !queue.isEmpty else { return false }
        let nextID = queue.removeFirst()
        guard let next = resolve(nextID) else { return false }
        setEpisode(next)
        play()
        return true
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

        // Throttled snapshot write — at most once every 5 seconds. The widget
        // re-reads on a 60s timeline, so finer writes are pure waste.
        writeNowPlayingSnapshot(force: false)

        // Natural end-of-item handler in `AudioEngine+Observers` pins
        // `currentTime` to exactly `duration`. A 0.1s tolerance absorbs any
        // observer jitter without misclassifying a manual pause near the end.
        let total = duration
        if total > 0, time >= total - 0.1, !isPlaying {
            // Always remember we hit the end so the persistence loop stops
            // re-writing the final position. Whether we *also* mark the episode
            // played is an explicit user preference.
            didFireFinishedFor = episode.id
            if autoMarkPlayedOnFinish {
                // markEpisodePlayed flushes the cache itself, so the
                // explicit flush below would be redundant on this path.
                onEpisodeFinished(episode.id)
            } else {
                // Auto-mark is off: we just persisted the final position
                // through `onPersistPosition` above, which goes through
                // the debounced cache. Force it to disk now so the user's
                // exact end-position survives a kill before the next
                // debounce tick.
                onFlushPositions()
            }
        }
    }

    /// Writes the current episode metadata into the App Group `UserDefaults`
    /// the widget reads from, then nudges WidgetKit to refresh. Throttled to
    /// once per 5s unless `force` is set (e.g. on episode change), where the
    /// snapshot must update immediately.
    private func writeNowPlayingSnapshot(force: Bool) {
        guard let episode else { return }
        let now = Date()
        if !force, let last = lastSnapshotWrite,
           now.timeIntervalSince(last) < 5 {
            return
        }
        let snapshot = NowPlayingSnapshot(
            episodeTitle: episode.title,
            showName: resolveShowName(episode),
            imageURLString: episode.imageURL?.absoluteString,
            position: engine.currentTime,
            duration: duration,
            updatedAt: now,
            // Reuse the engine's chapter resolver — same closure that drives
            // the lock-screen album line. `nil` for chapter-less episodes
            // so the widget falls back cleanly to show name only.
            chapterTitle: engine.resolveActiveChapterTitle(episode, engine.currentTime)
        )
        NowPlayingSnapshotStore.write(snapshot)
        lastSnapshotWrite = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
