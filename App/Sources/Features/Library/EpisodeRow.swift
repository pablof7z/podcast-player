import SwiftUI

// MARK: - EpisodeRow

/// Episode list row for the show-detail screen.
///
/// **State surfaces:**
///   - Unplayed:     leading red `circle.fill` dot, bold title.
///   - In progress:  leading `circle.lefthalf.filled` "crescent".
///   - Played:       leading `checkmark.circle.fill`, dimmed title.
///   - Downloading:  2 px progress bar (primary color) pinned to bottom edge.
///   - Transcribing: 2 px progress bar (accent color) pinned to bottom edge.
///   - Downloaded:   title at full opacity; not-yet-downloaded titles are muted.
struct EpisodeRow: View {
    let episode: Episode
    let showAccent: Color
    /// Tap action for the leading state indicator. `nil` means the indicator
    /// is decorative (the historical default); supplying it converts the
    /// indicator into a Play affordance that loads the episode into the
    /// mini-player without leaving the list.
    var onPlay: (() -> Void)? = nil

    /// Live progress map — drives the bottom progress bar without hitting
    /// `AppStateStore` on every 5%/200 ms tick.
    @State private var downloadService = EpisodeDownloadService.shared

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            playOrIndicator
                .frame(width: 22, alignment: .center)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(episode.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                let summary = episode.plainTextSummary
                if !summary.isEmpty {
                    Text(summary)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                metaRow
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .overlay(alignment: .bottom) { downloadProgressBar }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    /// Wraps the state indicator in a tap target when `onPlay` is supplied.
    /// Decorative when not — preserves call sites that don't need play.
    @ViewBuilder
    private var playOrIndicator: some View {
        if let onPlay {
            Button {
                Haptics.medium()
                onPlay()
            } label: {
                stateIndicator
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Play \(episode.title)")
        } else {
            stateIndicator
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        if episode.played {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if episode.isInProgress {
            Image(systemName: "circle.lefthalf.filled")
                .font(.body)
                .foregroundStyle(showAccent)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        }
    }

    private var metaRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(episode.formattedDuration)
                .font(AppTheme.Typography.monoCaption)
                .foregroundStyle(.secondary)

            Text("·")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.tertiary)

            Text(relativePublished)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)

            if episode.isInProgress {
                Text("·")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                Text("\(Int((episode.playbackProgress * 100).rounded()))% in")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(showAccent)
            }
        }
    }

    // MARK: - Helpers

    /// Mutes the title for not-yet-downloaded episodes so the user can
    /// distinguish locally available episodes at a glance. Played episodes
    /// stay secondary regardless of download state.
    private var titleColor: Color {
        if episode.played { return .secondary }
        if case .downloaded = episode.downloadState { return .primary }
        return Color.primary.opacity(0.55)
    }

    @ViewBuilder
    private var downloadProgressBar: some View {
        if case .downloading(let persisted, _) = episode.downloadState {
            let p = (downloadService.progress[episode.id] ?? persisted).clamped01
            thinProgressBar(progress: p, color: Color.primary)
        } else if case .downloaded = episode.downloadState,
                  case .transcribing(let p) = episode.transcriptState {
            thinProgressBar(progress: p.clamped01, color: Color.accentColor)
        }
    }

    private func thinProgressBar(progress: Double, color: Color) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(color)
                .frame(width: geo.size.width * progress, height: 2)
        }
        .frame(height: 2)
    }

    private var relativePublished: String {
        Self.relativeFormatter.localizedString(for: episode.pubDate, relativeTo: Date())
    }

    /// Cached — `EpisodeRow` is the per-row view inside a show's
    /// episode list, so a 200-episode show was minting 200
    /// `RelativeDateTimeFormatter` instances per render.
    /// `RelativeDateTimeFormatter` is reentrant for `localizedString(...)`.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var accessibilityLabel: String {
        var parts: [String] = [episode.title]
        parts.append(episode.formattedDuration)
        if episode.played {
            parts.append("played")
        } else if episode.isInProgress {
            parts.append("\(Int((episode.playbackProgress * 100).rounded())) percent listened")
        } else {
            parts.append("unplayed")
        }
        switch episode.downloadState {
        case .downloading(let persisted, _):
            let pct = Int(((downloadService.progress[episode.id] ?? persisted).clamped01 * 100).rounded())
            parts.append("downloading \(pct) percent")
        case .downloaded:
            switch episode.transcriptState {
            case .transcribing(let p):
                parts.append("transcribing \(Int((p.clamped01 * 100).rounded())) percent")
            case .queued, .fetchingPublisher:
                parts.append("transcript queued")
            case .ready:
                parts.append("transcript available")
            case .failed:
                parts.append("transcript failed")
            case .none:
                parts.append("downloaded")
            }
        case .failed:
            parts.append("download failed")
        case .queued:
            parts.append("download queued")
        case .notDownloaded:
            break
        }
        return parts.joined(separator: ", ")
    }
}
