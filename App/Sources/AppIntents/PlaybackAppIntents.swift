import AppIntents
import Foundation
import os.log

private let intentLog = Logger(subsystem: "io.f7z.podcast", category: "AppIntents")

// MARK: - PlayLatestEpisodeIntent

/// "Play my podcasts" — dispatches `podcast.siri.play_latest`. The kernel
/// picks the most-recently-published unplayed episode (D0, D7: policy in
/// Rust). Works hands-free from Siri, Shortcuts, and CarPlay.
struct PlayLatestEpisodeIntent: AppIntent {

    static let title: LocalizedStringResource = "Play latest episode"

    static let description = IntentDescription(
        "Play the most recently published unplayed episode from your library.",
        categoryName: "Playback"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = KernelModel.shared else {
            intentLog.error("PlayLatestEpisodeIntent: KernelModel.shared is nil")
            return .result(dialog: "Pod0 isn't ready yet. Try again in a moment.")
        }
        model.dispatch(namespace: "podcast.siri", body: ["op": "play_latest"])
        intentLog.info("PlayLatestEpisodeIntent: dispatched podcast.siri.play_latest")
        return .result(dialog: "Playing the latest episode.")
    }
}

// MARK: - PausePlaybackIntent

/// "Pause podcast" — dispatches `podcast.player.pause`. The kernel
/// drops the pause silently when nothing is playing (D6).
struct PausePlaybackIntent: AppIntent {

    static let title: LocalizedStringResource = "Pause podcast"

    static let description = IntentDescription(
        "Pause the currently-playing podcast episode.",
        categoryName: "Playback"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = KernelModel.shared else {
            intentLog.error("PausePlaybackIntent: KernelModel.shared is nil")
            return .result(dialog: "Pod0 isn't ready yet.")
        }
        model.dispatch(namespace: "podcast.player", body: ["op": "pause"])
        intentLog.info("PausePlaybackIntent: dispatched pause")
        return .result(dialog: "Paused.")
    }
}

// MARK: - ResumePlaybackIntent

/// "Resume podcast" — dispatches `podcast.siri.resume` and lets the Rust
/// kernel decide which episode to resume (D0, D7: policy in Rust). The
/// kernel replays the last-staged episode, or falls back to the latest
/// unplayed if nothing was staged.
struct ResumePlaybackIntent: AppIntent {

    static let title: LocalizedStringResource = "Resume podcast"

    static let description = IntentDescription(
        "Resume the last-playing podcast episode.",
        categoryName: "Playback"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = KernelModel.shared else {
            intentLog.error("ResumePlaybackIntent: KernelModel.shared is nil")
            return .result(dialog: "Pod0 isn't ready yet.")
        }
        model.dispatch(namespace: "podcast.siri", body: ["op": "resume"])
        intentLog.info("ResumePlaybackIntent: dispatched podcast.siri.resume")
        return .result(dialog: "Resuming.")
    }
}

// MARK: - SkipForwardIntent

/// "Skip forward" — dispatches `podcast.player.skip_forward` with the
/// user's configured interval. The Rust kernel reads the live player
/// position and emits an absolute seek so iOS never needs to know the
/// current time (D0 — policy in Rust).
struct SkipForwardIntent: AppIntent {

    static let title: LocalizedStringResource = "Skip forward"

    static let description = IntentDescription(
        "Skip the currently-playing podcast episode forward by the configured interval.",
        categoryName: "Playback"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = KernelModel.shared else {
            intentLog.error("SkipForwardIntent: KernelModel.shared is nil")
            return .result(dialog: "Pod0 isn't ready yet.")
        }
        guard model.nowPlaying != nil else {
            intentLog.info("SkipForwardIntent: no active episode; dropping skip")
            return .result(dialog: "Nothing is playing.")
        }
        let secs = model.settings.skipForwardSecs
        model.dispatch(
            namespace: "podcast.player",
            body: ["op": "skip_forward", "secs": secs]
        )
        intentLog.info("SkipForwardIntent: dispatched skip_forward \(secs)s")
        return .result(dialog: "Skipped forward.")
    }
}
