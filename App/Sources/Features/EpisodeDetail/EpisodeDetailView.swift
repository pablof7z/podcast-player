import SwiftUI

// MARK: - EpisodeDetailView

/// Episode Detail surface. Three modes per UX-03 §3:
///   - **detail** — magazine cover (artwork hero, summary lede, chapters,
///     show notes, "Read transcript" CTA, floating glass player).
///   - **reading** — pure prose, player vanishes, single column.
///   - **followAlong** — transcript visible while audio plays, chapter rail
///     trailing edge, docked glass pill player.
///
/// Wired to **mock Episode + Transcript** until Lanes 1+2 plug their real
/// types in. Player chrome is a placeholder pill (see
/// `DockedPlayerPlaceholder`) so we don't conflict with Lane 4 — the brief
/// explicitly says we own dock geometry, not player internals.
struct EpisodeDetailView: View {

    // MARK: Mode

    enum Mode: Hashable, CaseIterable, Sendable {
        case detail
        case reading
        case followAlong
    }

    // MARK: Inputs

    let episode: MockEpisode
    let transcript: Transcript

    // MARK: State

    @State private var mode: Mode = .detail
    @State private var currentTime: TimeInterval = 0
    @State private var sharingSegment: Segment?

    init(episode: MockEpisode, transcript: Transcript) {
        self.episode = episode
        self.transcript = transcript
    }

    /// Convenience initialiser for previews and Lane 5 standalone use.
    static func mock() -> some View {
        let (episode, transcript) = MockEpisodeFixture.timFerrissKeto()
        return EpisodeDetailView(episode: episode, transcript: transcript)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            playerChrome
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { modeToolbar }
        .sheet(item: $sharingSegment) { seg in
            QuoteShareView(
                episode: episode,
                segment: seg,
                speaker: transcript.speaker(for: seg.speakerID),
                deepLink: "podcast.app/e/\(episode.episodeNumber ?? 0)?t=\(Int(seg.start))"
            )
        }
    }

    // MARK: - Content per mode

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .detail:
            EpisodeDetailHeroView(
                episode: episode,
                onPlayChapter: { chapter in
                    currentTime = chapter.start
                    withAnimation(.spring(duration: 0.45, bounce: 0.12)) { mode = .followAlong }
                },
                onReadTranscript: {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { mode = .reading }
                }
            )
        case .reading:
            TranscriptReaderView(
                episode: episode,
                transcript: transcript,
                currentTime: nil,
                followAlong: false,
                onJump: { _ in mode = .followAlong },
                onShare: { sharingSegment = $0 }
            )
        case .followAlong:
            ZStack(alignment: .trailing) {
                TranscriptReaderView(
                    episode: episode,
                    transcript: transcript,
                    currentTime: currentTime,
                    followAlong: true,
                    onJump: { currentTime = $0 },
                    onShare: { sharingSegment = $0 }
                )
                ChapterRailView(
                    chapters: episode.chapters,
                    activeID: activeChapterID,
                    onTap: { currentTime = $0.start }
                )
                .padding(.trailing, AppTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Player chrome

    @ViewBuilder
    private var playerChrome: some View {
        switch mode {
        case .detail, .followAlong:
            DockedPlayerPlaceholder(
                title: episode.title,
                subtitle: episode.showName,
                currentTime: currentTime,
                duration: episode.duration
            )
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.md)
        case .reading:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        switch mode {
        case .detail: return episode.showName
        case .reading: return "Reader"
        case .followAlong: return activeChapterTitle ?? "Now Playing"
        }
    }

    private var activeChapterID: UUID? {
        guard let chapter = episode.chapters.last(where: { $0.start <= currentTime })
        else { return episode.chapters.first?.id }
        return chapter.id
    }

    private var activeChapterTitle: String? {
        episode.chapters.last(where: { $0.start <= currentTime })?.title
    }

    @ToolbarContentBuilder
    private var modeToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $mode) {
                Text("Detail").tag(Mode.detail)
                Text("Read").tag(Mode.reading)
                Text("Along").tag(Mode.followAlong)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }
}

// MARK: - Preview

#Preview("Detail") { NavigationStack { EpisodeDetailView.mock() } }
