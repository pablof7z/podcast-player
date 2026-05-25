import SwiftUI

// MARK: - EpisodeRoute

/// Navigation value pushed onto a `NavigationStack` to open `EpisodeDetailView`.
///
/// We carry the surrounding `PodcastSummary` along with the `EpisodeSummary`
/// so the detail view can render fallback artwork and the show title without
/// re-querying the kernel snapshot for the parent podcast.
struct EpisodeRoute: Hashable {
    let episode: EpisodeSummary
    let podcast: PodcastSummary
}

// MARK: - EpisodeDetailView

/// NMP-native episode detail screen. Backed entirely by `EpisodeSummary` from
/// the kernel snapshot — no `AppStateStore`, no compat types.
///
/// Show notes are intentionally omitted: `EpisodeSummary` does not yet project
/// a description field. Tracked in `docs/BACKLOG.md` as
/// `pr10-episode-description-projection`.
struct EpisodeDetailView: View {
    let episode: EpisodeSummary
    let podcast: PodcastSummary

    @Environment(KernelModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                artwork
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(episode.title)
                        .font(AppTheme.Typography.title)
                        .multilineTextAlignment(.leading)

                    Text(podcast.title)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(.secondary)
                }

                metaRow

                playButton
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Live snapshot

    /// Re-read the player state so the play/pause label tracks transport.
    private var nowPlaying: PlayerState? { model.podcastSnapshot?.nowPlaying }

    private var isThisEpisodePlaying: Bool {
        nowPlaying?.episodeId == episode.id && nowPlaying?.isPlaying == true
    }

    // MARK: - Artwork

    private var artworkURL: URL? {
        if let s = episode.artworkUrl, let url = URL(string: s) { return url }
        if let s = podcast.artworkUrl, let url = URL(string: s) { return url }
        return nil
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous)
        Group {
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.18)
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Meta

    @ViewBuilder
    private var metaRow: some View {
        let hasDuration = episode.durationSecs != nil
        let hasDate = episode.publishedAt != nil
        if hasDuration || hasDate {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let secs = episode.durationSecs {
                    Label(formatDuration(secs), systemImage: "clock")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if hasDuration && hasDate {
                    Text("·")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
                if let ts = episode.publishedAt {
                    Label(absoluteDate(from: ts), systemImage: "calendar")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .labelStyle(.titleAndIcon)
        }
    }

    // MARK: - Play button

    private var playButton: some View {
        Button {
            Haptics.medium()
            if isThisEpisodePlaying {
                model.dispatch(namespace: "podcast.player", body: ["op": "pause"])
            } else {
                model.dispatch(
                    namespace: "podcast.player",
                    body: ["op": "play", "episode_id": episode.id]
                )
                NotificationCenter.default.post(name: .openPlayerRequested, object: nil)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: isThisEpisodePlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(isThisEpisodePlaying ? "Pause" : "Play episode")
                    .font(AppTheme.Typography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isThisEpisodePlaying ? "Pause" : "Play \(episode.title)")
    }

    // Show notes are intentionally omitted until `EpisodeSummary` projects a
    // description field. See backlog item `pr10-episode-description-projection`.

    // MARK: - Formatting

    private func formatDuration(_ secs: Double) -> String {
        let total = Int(secs)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func absoluteDate(from unixSeconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
