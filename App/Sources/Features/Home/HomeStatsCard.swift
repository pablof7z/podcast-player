import SwiftUI

// MARK: - HomeStatsCard

/// A compact summary card shown at the top of the Home list when there is
/// meaningful activity to report.
///
/// Displays two stats side-by-side:
/// - **Pending** — active item count, with an overdue sub-label when items are past due.
///   Tapping navigates to the overdue filter when overdue items exist.
/// - **Done today** — items completed on the current calendar day
///   (tap navigates to CompletedItemsView).
///
/// The card is hidden when both counts are zero so it doesn't compete with the
/// `ContentUnavailableView` empty-state shown when the list has no items.
struct HomeStatsCard: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Divider height between the two stat cells.
        static let dividerHeight: CGFloat = 32
        /// Size of each stat's leading SF Symbol.
        static let iconSize: CGFloat = 16
    }

    // MARK: - Inputs

    let pendingCount: Int
    /// Non-zero when some pending items have a due date in the past.
    let overdueCount: Int
    let completedTodayCount: Int
    /// Non-zero when some pending items are flagged as priority.
    var priorityCount: Int = 0
    /// Non-zero when some pending items are due within the next 7 days (excluding overdue).
    var dueThisWeekCount: Int = 0
    var onShowCompleted: () -> Void
    /// Called when the user taps the pending cell while overdue items exist.
    /// When `nil`, the overdue count is shown as read-only text.
    var onShowOverdue: (() -> Void)? = nil
    /// Called when the user taps the "Due This Week" cell.
    /// When `nil`, the cell is shown but is not interactive.
    var onShowDueThisWeek: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            pendingStat
            Divider()
                .frame(height: Layout.dividerHeight)
            if dueThisWeekCount > 0 {
                dueThisWeekStat
                Divider()
                    .frame(height: Layout.dividerHeight)
            }
            completedTodayStat
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: AppTheme.Corner.lg)
        .padding(.vertical, AppTheme.Spacing.xs)
        .animation(AppTheme.Animation.spring, value: overdueCount > 0)
        .animation(AppTheme.Animation.spring, value: dueThisWeekCount > 0)
    }

    // MARK: - Subviews

    private var pendingStat: some View {
        Button {
            onShowOverdue?()
        } label: {
            VStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: overdueCount > 0 ? "exclamationmark.circle" : "circle.dotted")
                        .font(.system(size: Layout.iconSize, weight: .medium))
                        .foregroundStyle(overdueCount > 0 ? Color.red : Color.accentColor)
                        .accessibilityHidden(true)
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(pendingCount)")
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("pending")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                if overdueCount > 0 {
                    Text("\(overdueCount) overdue")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if priorityCount > 0 {
                    Text("\(priorityCount) starred")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(.orange)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .buttonStyle(.plain)
        .disabled(overdueCount == 0 || onShowOverdue == nil)
        .accessibilityLabel({
            if overdueCount > 0 { return "\(pendingCount) pending, \(overdueCount) overdue. Tap to filter." }
            if priorityCount > 0 { return "\(pendingCount) pending, \(priorityCount) starred." }
            return "\(pendingCount) pending"
        }())
    }

    private var dueThisWeekStat: some View {
        Button {
            onShowDueThisWeek?()
        } label: {
            statCell(
                value: dueThisWeekCount,
                label: "this week",
                icon: "calendar.badge.clock",
                iconColor: .orange
            )
        }
        .buttonStyle(.plain)
        .disabled(onShowDueThisWeek == nil)
        .accessibilityLabel("\(dueThisWeekCount) item\(dueThisWeekCount == 1 ? "" : "s") due this week. Tap to filter.")
    }

    private var completedTodayStat: some View {
        Button(action: onShowCompleted) {
            statCell(
                value: completedTodayCount,
                label: "done today",
                icon: "checkmark.circle.fill",
                iconColor: .green
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View completed items")
        .accessibilityHint("\(completedTodayCount) item\(completedTodayCount == 1 ? "" : "s") completed today")
    }

    private func statCell(
        value: Int,
        label: String,
        icon: String,
        iconColor: Color
    ) -> some View {
        VStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text("\(value)")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
    }
}
