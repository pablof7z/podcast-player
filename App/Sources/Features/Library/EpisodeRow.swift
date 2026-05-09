import SwiftUI

// MARK: - EpisodeRow

/// Episode list row for the show-detail screen.
///
/// **Glass usage:** matte. The row sits on the elevated card surface and uses
/// the system grouped-list look. The only glass-y element on this row is
/// `DownloadStatusCapsule` (which is itself a structural status indicator,
/// not a card).
///
/// **State surfaces:**
///   - Unplayed:    leading red `circle.fill` dot, bold title.
///   - In progress: leading `circle.lefthalf.filled` "crescent".
///   - Played:      leading `checkmark.circle.fill`, dimmed title.
///   - Downloaded:  trailing `DownloadStatusCapsule`.
///   - Transcribing/queued: trailing capsule communicates state.
struct EpisodeRow: View {
    let episode: Episode
    let showAccent: Color
    /// Tap action for the leading state indicator. `nil` means the indicator
    /// is decorative (the historical default); supplying it converts the
    /// indicator into a Play affordance that loads the episode into the
    /// mini-player without leaving the list.
    var onPlay: (() -> Void)? = nil

    /// Live download service — observed so the trailing capsule's
    /// "Downloading N%" label updates smoothly without each tick hitting
    /// `AppStateStore` (which would re-persist + re-spotlight + reload
    /// widgets on every progress event).
    @State private var downloadService = EpisodeDownloadService.shared

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            playOrIndicator
                .frame(width: 22, alignment: .center)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(episode.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(episode.played ? Color.secondary : Color.primary)
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

            Spacer(minLength: AppTheme.Spacing.xs)

            DownloadStatusCapsule(
                status: episode.displayDownloadStatus,
                liveProgress: downloadService.progress[episode.id]
            )
        }
    }

    // MARK: - Helpers

    private var relativePublished: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: episode.pubDate, relativeTo: Date())
    }

    /// Compound VoiceOver label per ux-02 §8 — title, duration, played-state,
    /// transcript-status read as one phrase.
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
        switch episode.displayDownloadStatus {
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
