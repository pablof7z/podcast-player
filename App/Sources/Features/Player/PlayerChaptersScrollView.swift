import SwiftUI

// MARK: - PlayerChaptersScrollView

/// Chapter rail for the full-screen `PlayerView`.
///
/// Renders a non-scrolling `LazyVStack` of chapter rows — the parent owns the
/// `ScrollView` so chapters scroll naturally with the rest of the page
/// (artwork header → chapters) instead of in a self-contained box. Visual
/// idiom is lifted from `EpisodeDetailHeroView.chaptersSection` (monospace
/// timestamp column + serif title) so the reading surface feels editorially
/// consistent with the episode-detail surface.
///
/// Active chapter is highlighted; the parent handles one-time scroll-to-
/// active on open via its own `ScrollViewReader` (we intentionally don't
/// re-center on every boundary crossing — that would jerk the whole page
/// roughly once per minute). Tap to seek; if the player is paused on a
/// fresh open, also start playback so the user doesn't need a follow-up tap.
struct PlayerChaptersScrollView: View {

    let chapters: [Episode.Chapter]
    @Bindable var state: PlaybackState

    /// Live store handle — needed for the long-press "Ask agent about this
    /// chapter" dispatch, which mirrors the transcript-row pattern by
    /// writing a `ChapterAgentContext` and posting `.askAgentRequested`.
    @Environment(AppStateStore.self) private var store

    /// The chapter that contains the current playhead — see
    /// `Collection<Episode.Chapter>.active(at:)` for the resolution rule.
    private var activeChapterID: UUID? {
        chapters.active(at: state.currentTime)?.id
    }

    /// Detected ad spans for the currently-loaded episode. Read live via the
    /// store rather than `PlaybackState.adSegments` so a detection result
    /// that lands while the player surface is open (e.g. the user opened a
    /// freshly-ingested episode) reflects on the rail immediately. The
    /// auto-skip path still goes through `PlaybackState.adSegments` for
    /// per-tick efficiency.
    private var adSegments: [Episode.AdSegment] {
        guard let id = state.episode?.id,
              let episode = store.episode(id: id) else { return [] }
        return episode.adSegments ?? []
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            ForEach(chapters) { chapter in
                chapterRow(chapter, isActive: chapter.id == activeChapterID)
                    .id(chapter.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chapters")
    }

    // MARK: - Row

    @ViewBuilder
    private func chapterRow(_ chapter: Episode.Chapter, isActive: Bool) -> some View {
        let overlapsAd = chapter.overlapsAd(in: chapters, adSegments: adSegments)
        Button {
            handleTap(chapter)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(chapter.title)
                    .font(.system(.body).weight(isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if overlapsAd {
                    Image(systemName: "speaker.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Tint.warning)
                        .accessibilityLabel("Contains an ad")
                }
                Text(formatTimestamp(chapter.startTime))
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .overlay(alignment: .leading) {
                if overlapsAd {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(AppTheme.Tint.warning)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chapter.title)
        .accessibilityValue(isActive ? "Active chapter, \(formatTimestamp(chapter.startTime))" : formatTimestamp(chapter.startTime))
        .accessibilityHint("Seeks playback to this chapter")
        .contextMenu {
            Button {
                askAgent(about: chapter)
            } label: {
                Label("Ask agent about this chapter", systemImage: "sparkles")
            }
        }
    }

    /// Long-press → "Ask the agent about this chapter." Forwards to
    /// `ChapterAskAgentDispatcher`, which writes a `ChapterAgentContext`
    /// (chapter title + time range — no transcript text) and posts the
    /// `askAgentRequested` notification `RootView` observes to present the
    /// agent chat sheet.
    private func askAgent(about chapter: Episode.Chapter) {
        ChapterAskAgentDispatcher.dispatch(
            chapter: chapter,
            in: chapters,
            episode: state.episode,
            store: store
        )
    }

    // MARK: - Behavior

    private func handleTap(_ chapter: Episode.Chapter) {
        // Seek every time the user taps a chapter; only auto-resume on
        // a fresh open (currentTime ≈ 0). A user who deliberately paused
        // mid-playback to read chapter titles ahead would otherwise lose
        // their pause every time they explored the list.
        let isFreshSession = state.currentTime <= 0.5
        Haptics.selection()
        state.navigationalSeek(to: chapter.startTime)
        if !state.isPlaying && isFreshSession {
            state.play()
        }
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        // Use the shared formatter — guards NaN/negative inputs from a
        // corrupt feed and keeps the zero-padded `%02d:%02d[:02d]` style
        // by branching on hours.
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
