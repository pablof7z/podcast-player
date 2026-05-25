import AppIntents
import Foundation

// MARK: - PodcastAppShortcuts
//
// `AppShortcutsProvider` is the only place an iOS app declares the
// natural-language phrases Siri / Shortcuts / Spotlight should index
// for each `AppIntent`. The system reads it at install time (and
// whenever `updateAppShortcutParameters()` is called from the host
// app) and surfaces the listed phrases in:
//   - Siri ("Hey Siri, play my latest podcast")
//   - Spotlight search results
//   - the Shortcuts app's "App Shortcuts" gallery
//   - the lock-screen / Action-Button / AirPods shortcut pickers
//
// Doctrine:
//   - Phrases use `\(.applicationName)` so a re-branded build (the
//     `appDisplayName` in `Project.swift` / `project.yml`) ships the
//     correct utterance without code changes.
//   - One `AppShortcut` per intent. Multi-step shortcuts compose in
//     the Shortcuts app from these primitives — they are not
//     duplicated here.
//   - Short titles are <= 40 chars (Apple guidance) so they fit the
//     shortcut card UI without truncation.

struct PodcastAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLatestEpisodeIntent(),
            phrases: [
                "Play my latest podcast in \(.applicationName)",
                "Play the latest episode in \(.applicationName)",
                "Start a new podcast in \(.applicationName)",
            ],
            shortTitle: "Play latest episode",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause my podcast in \(.applicationName)",
            ],
            shortTitle: "Pause podcast",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Resume my podcast in \(.applicationName)",
                "Keep playing \(.applicationName)",
            ],
            shortTitle: "Resume podcast",
            systemImageName: "playpause.circle.fill"
        )
        AppShortcut(
            intent: SkipForwardIntent(),
            phrases: [
                "Skip forward in \(.applicationName)",
                "Skip 30 seconds in \(.applicationName)",
                "Fast forward \(.applicationName)",
            ],
            shortTitle: "Skip forward 30s",
            systemImageName: "goforward.30"
        )
    }
}
