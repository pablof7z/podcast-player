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
                Text(formatTimestamp(chapter.startTime))
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 60, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.system(.body))
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let summary = chapter.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isActive ? 4 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if overlapsAd {
                    Image(systemName: "speaker.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Tint.warning)
                        .accessibilityLabel("Contains an ad")
                }
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
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(rowBackground(isActive: isActive))
            .overlay(alignment: .leading) {
                if overlapsAd {
                    // Amber leading stripe — informational only. Tapping the
                    // row still seeks normally; the stripe just tells the
                    // user this chapter overlaps a detected ad span.
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
