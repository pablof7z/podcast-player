import SwiftUI

// MARK: - PlayerChaptersScrollView

/// Chapter-focused secondary surface inside the full-screen `PlayerView`.
///
/// Replaces the transcript scroller as the player's primary scrollable body
/// when the episode has navigable chapters. Visual idiom is lifted from
/// `EpisodeDetailHeroView.chaptersSection` (monospace timestamp column +
/// serif title) so the reading surface feels editorially consistent with
/// the episode-detail surface.
///
/// Active chapter is highlighted and auto-scrolled into view as `currentTime`
/// crosses each `startTime`. Tap to seek; if the player is paused, also start
/// playback so the user doesn't need a follow-up tap.
struct PlayerChaptersScrollView: View {

    let chapters: [Episode.Chapter]
    @Bindable var state: PlaybackState
    /// When `true`, wraps the rail in a glass card to match the standard
    /// hero-card framing PlayerView uses for its secondary surface.
    let useGlassCard: Bool

    /// The chapter that contains the current playhead — see
    /// `Collection<Episode.Chapter>.active(at:)` for the resolution rule.
    private var activeChapterID: UUID? {
        chapters.active(at: state.currentTime)?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(chapters) { chapter in
                        chapterRow(chapter, isActive: chapter.id == activeChapterID)
                            .id(chapter.id)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
                .padding(.horizontal, useGlassCard ? AppTheme.Spacing.md : 0)
            }
            .background(cardBackground)
            .onChange(of: activeChapterID) { _, newID in
                guard let newID else { return }
                withAnimation(AppTheme.Animation.spring) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chapters")
    }

    // MARK: - Row

    @ViewBuilder
    private func chapterRow(_ chapter: Episode.Chapter, isActive: Bool) -> some View {
        Button {
            handleTap(chapter)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(formatTimestamp(chapter.startTime))
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 60, alignment: .leading)
                Text(chapter.title)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "waveform")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating, value: state.isPlaying)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 8)
            .background(rowBackground(isActive: isActive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chapter.title)
        .accessibilityValue(isActive ? "Active chapter, \(formatTimestamp(chapter.startTime))" : formatTimestamp(chapter.startTime))
        .accessibilityHint("Double-tap to play from this chapter")
    }

    @ViewBuilder
    private func rowBackground(isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if useGlassCard {
            RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Behavior

    private func handleTap(_ chapter: Episode.Chapter) {
        Haptics.selection()
        state.seek(to: chapter.startTime)
        if !state.isPlaying {
            state.play()
        }
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
