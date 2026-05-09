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
/// passed `episodeID`. The transcript surface is intentionally placeholder
/// until the transcript ingestion lane lands — this view shows
/// `TranscribingInProgressView` for any non-`.ready` `transcriptState`.
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
        let transcript = readyTranscript(for: episode)

        ZStack(alignment: .bottom) {
            content(episode: episode,
                    showName: showName,
                    showImageURL: showImageURL,
                    transcript: transcript)
            playerChrome(episode: episode, showName: showName)
        }
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
                    playback.seek(to: chapter.startTime)
                    withAnimation(.spring(duration: 0.45, bounce: 0.12)) { mode = .followAlong }
                },
                onReadTranscript: {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { mode = .reading }
                }
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

    // MARK: - Player chrome

    @ViewBuilder
    private func playerChrome(episode: Episode, showName: String) -> some View {
        switch mode {
        case .detail, .followAlong:
            DockedPlayerPlaceholder(
                title: episode.title,
                subtitle: showName,
                currentTime: playback.currentTime,
                duration: episode.duration ?? playback.duration
            )
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.md)
        case .reading:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func navigationTitle(episode: Episode, showName: String) -> String {
        switch mode {
        case .detail: return showName
        case .reading: return "Reader"
        case .followAlong:
            if let chapters = navigableChapters(for: episode),
               let active = chapters.last(where: { $0.startTime <= playback.currentTime }) {
                return active.title
            }
            return "Now Playing"
        }
    }

    private func navigableChapters(for episode: Episode) -> [Episode.Chapter]? {
        episode.chapters?.filter(\.includeInTableOfContents)
    }

    private func activeChapterID(in chapters: [Episode.Chapter]) -> UUID? {
        guard let active = chapters.last(where: { $0.startTime <= playback.currentTime })
        else { return chapters.first?.id }
        return active.id
    }

    private func readyTranscript(for episode: Episode) -> Transcript? {
        // Transcript ingestion lane will populate a real store keyed by
        // `episode.id`. Until that lands, we can only surface what's already
        // marked `.ready` — and there's no fetcher in this lane to satisfy
        // it. Returning `nil` triggers the empty-state surface.
        guard case .ready = episode.transcriptState else { return nil }
        return nil
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
