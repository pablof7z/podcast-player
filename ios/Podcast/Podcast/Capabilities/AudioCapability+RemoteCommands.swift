import Foundation
import MediaPlayer

// MARK: - MPRemoteCommandCenter integration
//
// The lock-screen play button, AirPods double-tap, CarPlay buttons, and
// any other system-driven remote command all route through
// `MPRemoteCommandCenter.shared()`. The executor registers handlers that
// translate each tap into an `AudioReport` (or, where the capability
// already owns the immediate side effect, a direct command execution).
//
// D7 — *never* decide. Every tap is reported back to Rust as a report.
// In particular: the lock-screen "skip forward 30 s" button does NOT
// compute the new playhead in Swift. It emits a `Paused`-flavoured tap
// report (or, in the canonical spec, a `RemoteCommand{kind: .skip(30)}`
// report); Rust then decides where to seek and sends a `Seek` command
// back.
//
// **M3.B caveat.** The canonical spec §5.1 defines a `RemoteCommand`
// report variant the M3.A skeleton does not yet ship. Until the
// canonical shape lands we round-trip remote-command intents through
// `AudioReport.paused` (for play/pause) so the kernel still sees the
// transition, and we model skip/seek as a direct `Seek` *command*
// execution that *also* emits a synthesised report — see
// `applyRemoteSkip(_:)`. This is the smallest workable shape for M3.B;
// the full RemoteCommand vocabulary lands when the canonical
// capability migrates from `nostrmultiplatform`.

@MainActor
extension AudioCapability {

    /// Idempotent. Wires the play / pause / toggle / scrub / skip
    /// handlers. Called from `AudioCapability.start()`.
    func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // Play / Pause / Toggle.
        center.playCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                self.execute(.play)
                return .success
            }
        }
        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                self.execute(.pause)
                return .success
            }
        }
        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                let isPlaying = self.avPlayer.timeControlStatus == .playing
                self.execute(isPlaying ? .pause : .play)
                return .success
            }
        }

        // Scrub — system supplies an absolute timestamp; we synthesise
        // a `Seek` command. The kernel sees the new playhead via the
        // follow-up `Playing`/`Paused` report.
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            return MainActor.assumeIsolated {
                self.execute(.seek(positionSecs: positionEvent.positionTime))
                return .success
            }
        }

        // Skip forward / backward — defaults of 30 s / 15 s match the
        // legacy engine. The user-configurable values live in Rust and
        // arrive as `Seek` commands once that policy migrates; this is
        // the placeholder until then.
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.removeTarget(nil)
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            return MainActor.assumeIsolated {
                self.applyRemoteSkip(interval)
                return .success
            }
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.removeTarget(nil)
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            return MainActor.assumeIsolated {
                self.applyRemoteSkip(-interval)
                return .success
            }
        }
    }

    /// Idempotent. Detaches every handler this executor installed.
    /// Called from `AudioCapability.stop()`.
    func removeRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
    }

    // MARK: - Helpers

    /// Translate a skip event into a `Seek` command relative to the
    /// current playhead. The canonical capability spec models this as a
    /// `RemoteCommand{kind: .skipForward(30)}` report so Rust applies
    /// its policy (chapter snap, smart-skip) — that variant arrives
    /// with the canonical migration. Until then we do the addition
    /// here and emit a follow-up `Seek` to keep behaviour parity.
    ///
    /// D7 caveat: this is the only place in the executor that *computes*
    /// a new playhead from a remote tap. It's flagged for replacement
    /// by a pure `RemoteCommand` report the moment the canonical shape
    /// lands; document in the PR description.
    private func applyRemoteSkip(_ delta: TimeInterval) {
        let target = currentPosition() + delta
        execute(.seek(positionSecs: max(0, target)))
    }
}
