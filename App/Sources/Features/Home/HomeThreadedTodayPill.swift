import SwiftUI

// MARK: - HomeThreadedTodayPill
//
// Single-row affordance rendered below the agent picks rail in the Home
// featured section. Surfaces the most-mentioned topic across the user's
// unplayed library when at least three unplayed episodes mention it.
// Tapping it opens `HomeThreadedTodayView` as a half-sheet.
//
// Hidden entirely when no topic clears the threshold — the pill exists to
// celebrate the moment a thread has formed, not to perpetually advertise
// an empty state.

struct HomeThreadedTodayPill: View {
    let active: ThreadingInferenceService.ActiveTopic
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            onTap()
        }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "link.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Tint.agentSurface)
                (
                    Text("\(active.unplayedEpisodeCount) episodes touch on ")
                        .foregroundStyle(.primary)
                    + Text(active.topic.displayName)
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                    + Text(" — tap to thread")
                        .foregroundStyle(.secondary)
                )
                .font(AppTheme.Typography.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Corner.lg))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(active.unplayedEpisodeCount) episodes touch on \(active.topic.displayName). Tap to open the thread.")
    }
}
