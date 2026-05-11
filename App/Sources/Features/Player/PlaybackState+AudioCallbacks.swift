import Foundation

// MARK: - Audio callbacks

extension PlaybackState {

    /// Keep system-originated commands on the `PlaybackState` boundary so they
    /// get the same persistence, flushing, and snapshot side effects as UI taps.
    func configureAudioEngineCallbacks() {
        var callbacks = NowPlayingCenter.Callbacks()
        callbacks.play = { [weak self] in self?.play() }
        callbacks.pause = { [weak self] in self?.pause() }
        callbacks.toggle = { [weak self] in self?.togglePlayPause() }
        callbacks.skipForward = { [weak self] in self?.skipForward() }
        callbacks.skipBackward = { [weak self] in self?.skipBackward() }
        callbacks.seek = { [weak self] time in self?.seek(to: time) }
        callbacks.changeRate = { [weak self] rate in self?.setRate(rate) }
        engine.setNowPlayingCallbacks(callbacks)

        engine.onSleepTimerFire = { [weak self] in
            self?.pause()
        }
    }

    func setRate(_ newRate: Double) {
        engine.setRate(newRate)
    }
}
