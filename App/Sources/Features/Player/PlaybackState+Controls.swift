import Foundation

// MARK: - Playback controls

extension PlaybackState {

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let episode else { return }
        Haptics.medium()
        engine.play()
        ensureDownloadEnqueuedIfNeeded(for: episode)
        startPersistenceLoop()
        // Force-write the snapshot so the widget's play/pause glyph
        // flips immediately — the throttled persistence-loop write would
        // otherwise lag up to 5s.
        writeNowPlayingSnapshot(force: true)
    }

    func pause() {
        Haptics.soft()
        let pausedEpisodeID = episode?.id
        if engine.didReachNaturalEnd {
            tickPersistence()
        }
        guard episode?.id == pausedEpisodeID else { return }
        engine.pause()
        // Stop the 1-second persistence + snapshot loop while paused —
        // otherwise it keeps re-writing the same `currentTime` and
        // bouncing widget timelines for nothing, and races with the
        // pause flush below in pathological force-quit windows.
        // `play()` restarts the loop.
        persistenceTask?.cancel()
        persistenceTask = nil
        // Pause is a "the user is done for now" signal — drain the
        // position cache so the playhead survives a force-quit-after-
        // pause cycle. Cheap when the cache is empty.
        onFlushPositions()
        // Same reasoning as `play()` — keep the widget's glyph in sync
        // with the engine state without waiting on the next tick.
        writeNowPlayingSnapshot(force: true)
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
        Haptics.selection()
        persistAndFlushAfterUserSeek()
    }

    /// Delegates to `seek` — previously snapped to transcript words, kept
    /// for API compatibility with call sites that expect the snapping variant.
    func seekSnapping(to time: TimeInterval) {
        seek(to: time)
    }

    /// Skip backwards. Pass `nil` to honour the user's configured
    /// `skipBackwardSeconds`. Pass an explicit value for a specific delta
    /// (e.g. transcript chapter rewind).
    func skipBackward(_ seconds: TimeInterval? = nil) {
        engine.skip(back: seconds)
        persistAndFlushAfterUserSeek()
    }

    /// Skip forward. Pass `nil` to honour the user's configured
    /// `skipForwardSeconds`.
    func skipForward(_ seconds: TimeInterval? = nil) {
        engine.skip(forward: seconds)
        persistAndFlushAfterUserSeek()
    }

    /// Persists the post-seek position immediately and drains the cache.
    ///
    /// Without this, a user who scrubs/skips and then force-quits within
    /// the 30s position-debounce window resumes from the pre-seek
    /// position — the engine moved the playhead but the cache hadn't been
    /// touched yet (`tickPersistence` runs on a 1s timer). A user-initiated
    /// position change is the most explicit "remember where I am" signal we
    /// get; treat it like pause and flush eagerly.
    func persistAndFlushAfterUserSeek() {
        guard let episode else { return }
        let time = engine.currentTime
        if time > 0 {
            onPersistPosition(episode.id, time)
        }
        onFlushPositions()
    }

    func setRate(_ newRate: PlaybackRate) {
        engine.setRate(newRate.rawValue)
        Haptics.selection()
    }

    /// Effective skip intervals read from the engine so the lock-screen and
    /// in-app transport always agree. Surfaced for the UI to render the right
    /// SF Symbol glyph and the matching accessibility label.
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
        autoSkipAdsEnabled = settings.autoSkipAds
        headphoneDoubleTapAction = settings.headphoneDoubleTapAction
        headphoneTripleTapAction = settings.headphoneTripleTapAction
    }
}
