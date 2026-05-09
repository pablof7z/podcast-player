import Foundation
import Observation
import SwiftUI

// MARK: - Lane-local mock domain types
//
// These intentionally live inside the Player lane so the UI can be built and
// rendered without depending on Lane 1 (`AudioEngine`) or Lane 2 (`Podcast`).
// When Lane 1's real `Episode` and `PlaybackEngine` land, the binding contract
// documented in `docs/spec/work-reports/lane-04-player-ui.md` shows where to
// swap each property/method.

/// A minimal episode model the player UI binds against.
///
/// Lane 2's real `Episode` should expose at least these fields; Lane 1's
/// playback engine should publish a `MockPlayerEpisode`-shaped projection (or the
/// binding wrapper should adapt).
struct MockPlayerEpisode: Identifiable, Hashable {
    let id: String
    let showName: String
    let episodeNumber: Int?
    let title: String
    let chapterTitle: String?
    let duration: TimeInterval

    /// Two cover-art-extracted colors driving the wallpaper / speaker palette.
    /// Replace with `UIImage.dominantColors(...)` output once Lane 1 supplies
    /// real artwork loading.
    let primaryArtColor: Color
    let secondaryArtColor: Color
}

/// A single transcript line. `start`/`end` are absolute times into the episode.
struct MockTranscriptLine: Identifiable, Hashable {
    let id: Int
    let speakerID: String
    let speakerName: String
    let speakerColor: Color
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    /// `true` if the given playhead time is inside this line.
    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}

/// Playback rates surfaced in the speed sheet.
enum MockPlaybackRate: Double, CaseIterable, Identifiable {
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
}

/// Sleep-timer presets surfaced in the sleep-timer sheet.
enum MockSleepTimer: Hashable, Identifiable {
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

    static let presets: [MockSleepTimer] = [
        .off, .minutes(5), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfEpisode
    ]
}

// MARK: - MockPlaybackState

/// Drives the player UI with a fake playback timeline.
///
/// **Binding contract for Lane 1:** the real `AudioEngine` should publish the
/// same observable surface (`isPlaying`, `currentTime`, `duration`, `rate`,
/// `episode`, `transcript`) and accept the same imperative methods
/// (`togglePlayPause`, `seek`, `skipBackward`, `skipForward`, `setRate`,
/// `setSleepTimer`). The view layer should then point to that engine instead
/// of this mock; no other surface changes should be necessary.
@MainActor
@Observable
final class MockPlaybackState {

    // MARK: Observable playback state

    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var rate: MockPlaybackRate = .normal
    var sleepTimer: MockSleepTimer = .off
    var isAirPlayActive: Bool = false

    /// The current episode. `nil` when nothing is loaded — used by `RootView`
    /// to decide whether to mount the `MiniPlayerView`.
    var episode: MockPlayerEpisode?

    /// Sorted ascending by `start`.
    var transcript: [MockTranscriptLine] = []

    var duration: TimeInterval {
        episode?.duration ?? 0
    }

    /// Index into `transcript` for the line currently containing `currentTime`,
    /// or the closest preceding line when between lines. Returns `nil` only
    /// for an empty transcript.
    var activeLineIndex: Int? {
        guard !transcript.isEmpty else { return nil }
        // Linear is fine for ~40 lines; binary-search if Lane 1 streams large transcripts.
        var lastBefore = 0
        for (idx, line) in transcript.enumerated() {
            if line.contains(currentTime) { return idx }
            if line.start <= currentTime { lastBefore = idx }
        }
        return lastBefore
    }

    var activeLine: MockTranscriptLine? {
        activeLineIndex.map { transcript[$0] }
    }

    // MARK: Demo timer

    /// Drives `currentTime` forward while `isPlaying` is true. Lane 1 will
    /// remove this — real `AVPlayer` `addPeriodicTimeObserver` becomes the
    /// source of truth.
    private var demoTask: Task<Void, Never>?

    init() {
        loadDemoEpisode()
    }

    // MARK: Imperative methods (binding contract)

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            Haptics.medium()
            startDemoTimer()
        } else {
            Haptics.soft()
            demoTask?.cancel()
            demoTask = nil
        }
    }

    func play() {
        guard !isPlaying else { return }
        togglePlayPause()
    }

    func pause() {
        guard isPlaying else { return }
        togglePlayPause()
    }

    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        Haptics.selection()
    }

    /// Snap to nearest sentence boundary within ±400ms (UX-01 §5).
    func seekSnapping(to time: TimeInterval) {
        let target = max(0, min(time, duration))
        if let nearest = transcript.min(by: { abs($0.start - target) < abs($1.start - target) }),
           abs(nearest.start - target) <= 0.4 {
            currentTime = nearest.start
        } else {
            currentTime = target
        }
        Haptics.selection()
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func skipForward(_ seconds: TimeInterval = 30) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ rate: MockPlaybackRate) {
        self.rate = rate
        Haptics.selection()
    }

    func setSleepTimer(_ timer: MockSleepTimer) {
        self.sleepTimer = timer
        Haptics.selection()
    }

    func jumpToLine(_ line: MockTranscriptLine) {
        currentTime = line.start
        Haptics.light()
    }

    // MARK: Demo timer plumbing

    private func startDemoTimer() {
        demoTask?.cancel()
        demoTask = Task { @MainActor [weak self] in
            // Tick every ~120ms; fast enough for active-line transitions to
            // feel synced without flooding the run loop.
            while !Task.isCancelled {
                guard let strongSelf = self, strongSelf.isPlaying else { break }
                try? await Task.sleep(for: .milliseconds(120))
                guard let strongSelf = self, strongSelf.isPlaying else { break }
                let increment = 0.12 * strongSelf.rate.rawValue
                let next = strongSelf.currentTime + increment
                if next >= strongSelf.duration {
                    strongSelf.currentTime = strongSelf.duration
                    strongSelf.isPlaying = false
                    break
                }
                strongSelf.currentTime = next
            }
        }
    }

    // MARK: Demo data

    private func loadDemoEpisode() {
        let palette = MockTranscriptFixture.timFerrissKetoDemo
        episode = palette.episode
        transcript = palette.lines
        currentTime = palette.lines.first?.start ?? 0
    }
}
