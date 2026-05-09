import SwiftUI

// MARK: - HomeProgressHeader

/// Compact header row showing today's completion progress at a glance.
///
/// The "total" denominator is `doneCount + toGoCount` so the bar fills
/// completely as the last task is finished — when `toGoCount == 0` the
/// bar reaches 1.0 and the label switches to "All done!".
struct HomeProgressHeader: View {
    let doneCount: Int
    let toGoCount: Int
    /// Sum of `estimatedMinutes` across all pending active items. `0` when
    /// none have estimates set — the time chip is hidden in that case.
    let remainingMinutes: Int
    /// Consecutive-day completion streak. `0` or `1` hides the chip.
    let streak: Int

    private var progress: Double {
        let total = doneCount + toGoCount
        guard total > 0 else { return 0 }
        return Double(doneCount) / Double(total)
    }

    private var allDone: Bool { toGoCount == 0 }

    private var completionPercent: Int { Int(progress * 100) }

    /// Human-readable label for the total remaining estimated time.
    /// Returns `nil` when `remainingMinutes` is zero so callers can hide
    /// the chip cleanly without extra guard logic.
    private var remainingTimeLabel: String? {
        guard remainingMinutes > 0 else { return nil }
        if remainingMinutes < 60 {
            return "~\(remainingMinutes)m left"
        }
        let hours = remainingMinutes / 60
        let mins  = remainingMinutes % 60
        if mins == 0 {
            return "~\(hours)h left"
        }
        return "~\(hours)h \(mins)m left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("\(doneCount) done")
                    .foregroundStyle(.primary)
                if allDone {
                    Text("· All done!")
                        .foregroundStyle(.secondary)
                } else {
                    Text("· \(toGoCount) to go")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if allDone && doneCount > 0 {
                    dailyWinBadge
                } else if !allDone && doneCount > 0 {
                    Text("\(completionPercent)%")
                        .font(AppTheme.Typography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
                if !allDone, let timeLabel = remainingTimeLabel {
                    Label(timeLabel, systemImage: "clock")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
                if streak >= 1 {
                    streakChip
                }
            }
            .font(AppTheme.Typography.callout)

            ProgressView(value: progress, total: 1.0)
                .tint(allDone ? .green : .accentColor)
                .scaleEffect(y: 1.5, anchor: .center)
                .accessibilityLabel(allDone ? "Progress: all done" : "Progress: \(doneCount) done, \(toGoCount) to go")
                .accessibilityValue(allDone ? "100%" : "\(Int(progress * 100))%")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(AppTheme.Layout.cardRowInsetsSM)
        .listRowSeparator(.hidden)
        .animation(AppTheme.Animation.spring, value: progress)
        .animation(AppTheme.Animation.spring, value: remainingMinutes)
        .animation(AppTheme.Animation.spring, value: streak)
    }

    private var dailyWinBadge: some View {
        Label("Daily Win!", systemImage: "star.fill")
            .font(AppTheme.Typography.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .accessibilityLabel("Daily goal achieved")
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .accessibilityHidden(true)
            Text("\(streak)d")
                .fontWeight(.medium)
        }
        .font(AppTheme.Typography.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.12), in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .accessibilityLabel("\(streak) day streak")
    }
}
