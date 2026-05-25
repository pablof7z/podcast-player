import SwiftUI

/// Lists agent-generated TTS episodes surfaced by the Rust kernel via
/// `PodcastUpdate.ttsEpisodes` (feature #43).
///
/// Behaviour:
///
/// * Pull-style — the view never owns the list. Every render reads
///   `model.podcastSnapshot?.ttsEpisodes ?? []` so a kernel tick that
///   adds, removes, or transitions an episode lands here for free.
/// * The toolbar "Generate Episode" button presents
///   [`GenerateTtsSheet`], which dispatches `podcast.tts.generate`.
/// * Row play button dispatches `podcast.tts.play`; swipe-to-delete
///   dispatches `podcast.tts.delete`.
///
/// All dispatched actions go through `KernelModel.dispatch` so any
/// synchronous rejection surfaces in the global toast for free.
struct TtsEpisodesView: View {

    @Environment(KernelModel.self) private var model
    @State private var showGenerateSheet = false

    private var episodes: [TtsEpisodeSummary] {
        model.podcastSnapshot?.ttsEpisodes ?? []
    }

    var body: some View {
        Group {
            if episodes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("AI Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showGenerateSheet = true
                } label: {
                    Label("Generate Episode", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("tts-generate-button")
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            GenerateTtsSheet(isPresented: $showGenerateSheet)
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No AI Episodes Yet")
                .font(AppTheme.Typography.headline)
            Text("Generate a short narrated episode about any topic.")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)
            Button {
                showGenerateSheet = true
            } label: {
                Label("Generate Episode", systemImage: "plus.circle.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, AppTheme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        List {
            ForEach(episodes) { episode in
                TtsEpisodeRow(episode: episode) {
                    model.dispatch(
                        namespace: "podcast.tts",
                        body: ["op": "play", "episode_id": episode.id]
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        model.dispatch(
                            namespace: "podcast.tts",
                            body: ["op": "delete", "episode_id": episode.id]
                        )
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// One row in [`TtsEpisodesView`]. Renders title + status chip +
/// estimated duration + a circular play button on the trailing edge.
/// Pulled out into its own type so the parent stays under the soft
/// 300-LOC ceiling.
private struct TtsEpisodeRow: View {
    let episode: TtsEpisodeSummary
    let onPlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(episode.title)
                    .font(AppTheme.Typography.headline)
                    .lineLimit(2)
                HStack(spacing: AppTheme.Spacing.xs) {
                    statusChip
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(formattedDuration)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Text(episode.script)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play episode")
            .accessibilityIdentifier("tts-row-play-\(episode.id)")
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var statusChip: some View {
        Text(statusLabel)
            .font(AppTheme.Typography.caption2)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(statusBackground, in: Capsule())
            .foregroundStyle(statusForeground)
    }

    private var statusLabel: String {
        switch episode.status {
        case "generating_script": "Generating"
        case "ready": "Ready"
        case "played": "Played"
        default: episode.status.capitalized
        }
    }

    private var statusBackground: some ShapeStyle {
        switch episode.status {
        case "generating_script": Color.orange.opacity(0.18)
        case "ready": Color.accentColor.opacity(0.18)
        case "played": Color.secondary.opacity(0.18)
        default: Color.secondary.opacity(0.12)
        }
    }

    private var statusForeground: some ShapeStyle {
        switch episode.status {
        case "generating_script": Color.orange
        case "ready": Color.accentColor
        case "played": Color.secondary
        default: Color.secondary
        }
    }

    private var formattedDuration: String {
        let total = Int(episode.durationEstimateSecs.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "~\(minutes) min"
        }
        return "~\(seconds) sec"
    }
}
