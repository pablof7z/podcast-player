import SwiftUI

// MARK: - EpisodeDetailView

/// Episode Detail surface. Three modes per UX-03 §3:
///   - **detail** — magazine cover (artwork hero, summary lede, chapters,
///     show notes, "Read transcript" CTA, floating glass player).
///   - **reading** — pure prose, player vanishes, single column.
///   - **followAlong** — transcript visible while audio plays, chapter rail
///     trailing edge, docked glass pill player.
///
/// Driven by the real `Episode` looked up out of `AppStateStore` via the
/// passed `episodeID`. When `episode.transcriptState == .ready` the transcript
/// is loaded from `TranscriptStore`; otherwise we show
/// `TranscribingInProgressView`. On first appearance for an episode that has
/// a `publisherTranscriptURL` and a `.none` state, we kick off a background
/// `TranscriptIngestService` warm so the user's intent ("read this episode")
/// translates into a fetched transcript without an extra tap.
struct EpisodeDetailView: View {

    // MARK: Mode

    enum Mode: Hashable, CaseIterable, Sendable {
        case detail
        case reading
        case followAlong
    }

    // MARK: Inputs

    let episodeID: UUID

    // MARK: Environment

    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback

    // MARK: State

    @State private var mode: Mode = .detail
    @State private var sharingSegment: Segment?
    /// Live download service — observed so the toolbar's progress indicator
    /// updates smoothly without re-persisting `AppStateStore` on every tick.
    @State private var downloadService = EpisodeDownloadService.shared

    // MARK: Body

    var body: some View {
        Group {
            if let episode = store.episode(id: episodeID) {
                loaded(episode: episode)
            } else {
                missing
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loaded(episode: Episode) -> some View {
        let subscription = store.subscription(id: episode.subscriptionID)
        let showName = subscription?.title ?? "Podcast"
        let showImageURL = subscription?.imageURL
        let transcript = Self.readyTranscript(for: episode)

        // No inline player chrome — the global `MiniPlayerView` lives as
        // the tab's bottom accessory and is always visible while an episode
        // is loaded, so a second player surface here would duplicate it
        // (the previous `DockedPlayerPlaceholder` was a stub from an early
        // lane that never got removed).
        content(
            episode: episode,
            showName: showName,
            showImageURL: showImageURL,
            transcript: transcript
        )
        .navigationTitle(navigationTitle(episode: episode, showName: showName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { modeToolbar(hasTranscript: transcript != nil) }
        .toolbar { actionsToolbar(episode: episode) }
        .sheet(item: $sharingSegment) { seg in
            QuoteShareView(
                episode: episode,
                showName: showName,
                showImageURL: showImageURL,
                segment: seg,
                speaker: transcript?.speaker(for: seg.speakerID),
                deepLink: deepLink(for: episode, segment: seg)
            )
        }
        .task(id: episode.id) {
            await warmTranscriptIfNeeded(episode: episode)
            ChaptersHydrationService.shared.hydrateIfNeeded(
                episode: episode,
                store: store
            )
        }
    }

    /// Warm the transcript on first appearance. Strict gating: we only kick off
    /// an ingest if the state is `.none` and the publisher exposes a transcript
    /// URL. We deliberately do not retry `.failed` here — that's the user's
    /// "Request transcript" button to re-arm. We also don't try to gate on
    /// Scribe-only configs (no publisher URL); the explicit CTA in
    /// `TranscribingInProgressView` covers that path.
    private func warmTranscriptIfNeeded(episode: Episode) async {
        guard case .none = episode.transcriptState else { return }
        guard episode.publisherTranscriptURL != nil else { return }
        await TranscriptIngestService.shared.ingest(episodeID: episode.id)
    }

    // MARK: - Missing

    private var missing: some View {
        ContentUnavailableView(
            "Episode not found",
            systemImage: "questionmark.folder",
            description: Text("This episode is no longer in your library.")
        )
    }

    // MARK: - Content per mode

    @ViewBuilder
    private func content(episode: Episode,
                         showName: String,
                         showImageURL: URL?,
                         transcript: Transcript?) -> some View {
        switch mode {
        case .detail:
            EpisodeDetailHeroView(
                episode: episode,
                showName: showName,
                showImageURL: showImageURL,
                isPlayed: episode.played,
                onPlay: {
                    playback.setEpisode(episode)
                    playback.play()
                },
                onPlayChapter: { chapter in
                    // Tapping a chapter row in detail mode is "play this
                    // chapter" — make sure the episode is actually loaded
                    // and audio is rolling, not just an engine seek that
                    // silently no-ops when nothing is loaded yet.
                    if playback.episode?.id != episode.id {
                        playback.setEpisode(episode)
                    }
                    playback.seek(to: chapter.startTime)
                    if !playback.isPlaying {
                        playback.play()
                    }
                    // Only switch to follow-along when a transcript is
                    // ready. Without one, follow-along mode shows the
                    // "transcribing…" surface, which would hijack the
                    // user's screen for what was really just "play from
                    // here."
                    if Self.readyTranscript(for: episode) != nil {
                        withAnimation(.spring(duration: 0.45, bounce: 0.12)) { mode = .followAlong }
                    }
                },
                onReadTranscript: {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { mode = .reading }
                },
                isInQueue: playback.queue.contains(episode.id),
                onAddToQueue: {
                    Haptics.success()
                    playback.enqueue(episode.id)
                },
                activeChapterID: liveActiveChapterID(for: episode),
                downloadProgress: downloadService.progress[episode.id],
                onToggleDownload: { toggleDownload(episode: episode) }
            )
        case .reading:
            if let transcript {
                TranscriptReaderView(
                    episode: episode,
                    transcript: transcript,
                    currentTime: nil,
                    followAlong: false,
                    onJump: { _ in mode = .followAlong },
                    onShare: { sharingSegment = $0 }
                )
            } else {
                TranscribingInProgressView(episode: episode)
            }
        case .followAlong:
            if let transcript {
                ZStack(alignment: .trailing) {
                    TranscriptReaderView(
                        episode: episode,
                        transcript: transcript,
                        currentTime: playback.currentTime,
                        followAlong: true,
                        onJump: { playback.seek(to: $0) },
                        onShare: { sharingSegment = $0 }
                    )
                    if let chapters = navigableChapters(for: episode), !chapters.isEmpty {
                        ChapterRailView(
                            chapters: chapters,
                            activeID: activeChapterID(in: chapters),
                            onTap: { playback.seek(to: $0.startTime) }
                        )
                        .padding(.trailing, AppTheme.Spacing.sm)
                    }
                }
            } else {
                TranscribingInProgressView(episode: episode)
            }
        }
    }

    // MARK: - Helpers

    private func navigationTitle(episode: Episode, showName: String) -> String {
        switch mode {
        case .detail: return showName
        case .reading: return "Reader"
        case .followAlong:
            if let chapters = navigableChapters(for: episode),
               let active = chapters.active(at: playback.currentTime) {
                return active.title
            }
            return "Now Playing"
        }
    }

    private func navigableChapters(for episode: Episode) -> [Episode.Chapter]? {
        episode.chapters?.filter(\.includeInTableOfContents)
    }

    private func activeChapterID(in chapters: [Episode.Chapter]) -> UUID? {
        chapters.active(at: playback.currentTime)?.id
    }

    /// Active chapter id when this exact episode is currently loaded in
    /// the player. Returns `nil` for chapter-less episodes or when
    /// playback is on a different episode — the hero's chapter list
    /// renders flat in those cases.
    private func liveActiveChapterID(for episode: Episode) -> UUID? {
        guard playback.episode?.id == episode.id,
              let chapters = navigableChapters(for: episode),
              !chapters.isEmpty else { return nil }
        return activeChapterID(in: chapters)
    }

    /// Resolve the persisted `Transcript` for `episode` when its lifecycle is
    /// `.ready`. Returns `nil` for any other state (so the caller renders the
    /// in-progress / empty surface) and also `nil` if the on-disk file is
    /// missing — which can happen if the user wiped Application Support but
    /// the `AppState` snapshot still records `.ready`. Static + store-injected
    /// so tests can drive it with a temp-directory `TranscriptStore`.
    static func readyTranscript(
        for episode: Episode,
        store: TranscriptStore = .shared
    ) -> Transcript? {
        guard case .ready = episode.transcriptState else { return nil }
        return store.load(episodeID: episode.id)
    }

    /// Drives the inline Download pill on the hero. Mirrors the menu's
    /// state machine so the user can start, cancel, or retry from the
    /// primary surface — and sees a live "Downloading 42%" badge while
    /// bytes move (the persisted `downloadState` only updates at coarse
    /// transitions to spare AppStateStore from per-tick writes).
    private func toggleDownload(episode: Episode) {
        EpisodeDownloadService.shared.attach(appStore: store)
        switch episode.downloadState {
        case .notDownloaded, .queued, .failed:
            Haptics.success()
            EpisodeDownloadService.shared.download(episodeID: episode.id)
        case .downloading:
            Haptics.light()
            EpisodeDownloadService.shared.cancel(episodeID: episode.id)
        case .downloaded:
            // Inline pill is non-interactive in the downloaded state; the
            // ellipsis menu handles delete confirmation. No-op here so a
            // double-bind from a parent doesn't accidentally wipe the file.
            break
        }
    }

    private func deepLink(for episode: Episode, segment: Segment) -> String {
        let prefix = episode.guid.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? "ep"
        return "podcastr://e/\(prefix)?t=\(Int(segment.start))"
    }

    @ToolbarContentBuilder
    private func modeToolbar(hasTranscript: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $mode) {
                Text("Detail").tag(Mode.detail)
                Text("Read").tag(Mode.reading)
                if hasTranscript {
                    Text("Along").tag(Mode.followAlong)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    @ToolbarContentBuilder
    private func actionsToolbar(episode: Episode) -> some ToolbarContent {
        // Inline progress indicator — only present while a download is in
        // flight. Reads `EpisodeDownloadService.progress` directly so it
        // updates at the throttled service cadence (5% / 200ms) instead of
        // waiting on coarse `.downloaded` / `.failed` state writes.
        if case .downloading = episode.downloadState {
            ToolbarItem(placement: .topBarTrailing) {
                let live = downloadService.progress[episode.id] ?? 0
                ProgressView(value: live)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityLabel("Downloading \(Int(live * 100)) percent")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            EpisodeDetailActionsMenu(episode: episode, store: store)
        }
    }
}

// MARK: - Preview

#Preview("Detail") {
    let store = AppStateStore()
    let playback = PlaybackState()
    let subID = UUID()
    let subscription = PodcastSubscription(
        id: subID,
        feedURL: URL(string: "https://feeds.megaphone.fm/tim-ferriss")!,
        title: "The Tim Ferriss Show",
        author: "Tim Ferriss",
        description: "Deconstructing world-class performers."
    )
    let episode = Episode(
        subscriptionID: subID,
        guid: "preview-tim-ferriss-732",
        title: "How to Think About Keto",
        description: "<p>Tim sits down with <b>Peter Attia, MD</b> to revisit a topic the show has circled for years.</p>",
        pubDate: Date(timeIntervalSince1970: 1_714_780_800),
        duration: 60 * 60 * 2 + 14 * 60,
        enclosureURL: URL(string: "https://traffic.megaphone.fm/HSW1234567890.mp3")!,
        chapters: [
            .init(startTime: 0, title: "Cold open"),
            .init(startTime: 252, title: "Why ketones matter"),
            .init(startTime: 1720, title: "The Inuit objection"),
            .init(startTime: 4810, title: "Practical protocols")
        ]
    )
    store.state.subscriptions = [subscription]
    store.state.episodes = [episode]
    return NavigationStack {
        EpisodeDetailView(episodeID: episode.id)
    }
    .environment(store)
    .environment(playback)
}
