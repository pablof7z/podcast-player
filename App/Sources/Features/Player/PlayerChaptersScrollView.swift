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

    /// Live store handle — needed for the long-press "Ask agent about this
    /// chapter" dispatch, which mirrors the transcript-row pattern by
    /// writing a `ChapterAgentContext` and posting `.askAgentRequested`.
    @Environment(AppStateStore.self) private var store

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
            .onAppear {
                guard let activeChapterID else { return }
                proxy.scrollTo(activeChapterID, anchor: .center)
            }
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
                if chapter.isAIGenerated {
                    aiPill
                }
                Spacer(minLength: 0)
                if isActive {
                    // `speaker.wave.2.fill` reads as audible-from-this-row.
                    // The previous `waveform` glyph collided with the
                    // artwork-failure fallback in the hero (also a
                    // waveform), so chapter-less episodes with missing art
                    // showed a static waveform up top and an animated one
                    // mid-list — confusing.
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating, value: state.isPlaying)
                        .transition(.opacity.combined(with: .scale))
                        .accessibilityHidden(true)
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
        // Hint describes the *effect* of the action, not the gesture —
        // VoiceOver already announces "double-tap to activate" via the
        // button trait, so saying "double-tap to..." is redundant.
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

    /// Compact "AI" pill rendered next to chapter titles that came from
    /// `AIChapterCompiler` rather than the publisher feed. Uses the agent
    /// accent colour so AI-flavoured surfaces stay visually coherent.
    private var aiPill: some View {
        Text("AI")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(AppTheme.Tint.agentSurface)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(AppTheme.Tint.agentSurface.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(AppTheme.Tint.agentSurface.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel("AI-generated chapter")
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
        // Seek every time the user taps a chapter; only auto-resume on
        // a fresh open (currentTime ≈ 0). A user who deliberately paused
        // mid-playback to read chapter titles ahead would otherwise lose
        // their pause every time they explored the list.
        let isFreshSession = state.currentTime <= 0.5
        Haptics.selection()
        state.seek(to: chapter.startTime)
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
