import SwiftUI

// MARK: - EpisodeRow

/// Episode list row for the show-detail screen.
///
/// **Glass usage:** matte. The row sits on the elevated card surface
/// and uses the system grouped-list look. The lane brief reserves
/// structural glass for the nav chrome and the OPML sheet only —
/// the only glass-y element on this row is `DownloadStatusCapsule`
/// (which is itself a structural status indicator, not a card).
///
/// **State surfaces:**
///   - Unplayed:    leading red `circle.fill` dot, bold title.
///   - In progress: leading `circle.lefthalf.filled` "crescent".
///   - Played:      leading `checkmark.circle.fill`, dimmed title.
///   - Downloaded:  trailing `DownloadStatusCapsule`.
///   - Transcribing/queued: trailing capsule communicates state.
struct EpisodeRow: View {
    let episode: LibraryMockEpisode
    let showAccent: Color

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            stateIndicator
                .frame(width: 22, alignment: .center)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("#\(episode.number)  \(episode.title)")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(episode.isPlayed ? Color.secondary : Color.primary)
                    .lineLimit(2)

                Text(episode.summary)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                metaRow
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateIndicator: some View {
        if episode.isPlayed {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if episode.isInProgress {
            // Crescent for partial progress — matches ux-02 §3 wireframe.
            Image(systemName: "circle.lefthalf.filled")
                .font(.body)
                .foregroundStyle(showAccent)
                .accessibilityHidden(true)
        } else {
            // Unplayed — solid red dot, redundant with the bold title for
            // color-independence (per ux-02 §8 accessibility).
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

            Spacer(minLength: AppTheme.Spacing.xs)

            DownloadStatusCapsule(status: episode.downloadStatus)
        }
    }

    // MARK: - Helpers

    private var relativePublished: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: episode.publishedAt, relativeTo: Date())
    }

    /// Compound VoiceOver label per ux-02 §8 — episode number, title,
    /// duration, played-state, transcript-status read as one phrase.
    private var accessibilityLabel: String {
        var parts: [String] = ["Episode \(episode.number). \(episode.title)"]
        parts.append(episode.formattedDuration)
        if episode.isPlayed {
            parts.append("played")
        } else if episode.isInProgress {
            parts.append("\(Int((episode.playbackProgress * 100).rounded())) percent listened")
        } else {
            parts.append("unplayed")
        }
        switch episode.downloadStatus {
        case .none:                            break
        case .downloaded(let t):               parts.append(t ? "transcript available" : "downloaded")
        case .downloading(let p):              parts.append("downloading \(Int(p * 100)) percent")
        case .transcribing(let p):             parts.append("transcribing \(Int(p * 100)) percent")
        case .transcriptionQueued(let pos):    parts.append("queued at position \(pos)")
        case .failed:                          parts.append("failed")
        }
        return parts.joined(separator: ", ")
    }
}
