import SwiftUI

// MARK: - HomeEmptyState

/// Empty-state view for the home item list.
///
/// Handles three distinct cases:
/// - Active filter with no matches → "no results" with a clear-filter escape hatch.
/// - All items completed today → motivational trophy state with streak badge.
/// - Truly empty (no items, nothing completed) → onboarding prompt.
struct HomeEmptyState: View {

    private enum Layout {
        static let trophyIconSize: CGFloat = 52
    }

    let filter: HomeFilter
    let focusOverride: HomeFilter?
    let completedTodayCount: Int
    let completionStreak: Int
    let onClearFilter: () -> Void
    let onAddItem: () -> Void

    var body: some View {
        if filter.isActive {
            // Filter is narrowing the list — show a neutral "no matches" state
            // with an escape hatch to clear the filter.
            ContentUnavailableView {
                Label(filter.emptyTitle, systemImage: filter.icon)
            } description: {
                Text(filter.emptyDescription)
            } actions: {
                // Only allow clearing user-driven filters, not Focus overrides.
                if focusOverride == nil {
                    Button("Clear Filter", action: onClearFilter)
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)
        } else if completedTodayCount > 0 {
            // Everything done for the day — celebrate!
            motivationalState
        } else {
            // Truly empty (fresh install or clean slate with nothing completed).
            ContentUnavailableView {
                Label("Nothing to do", systemImage: "sparkles")
            } description: {
                Text("Tap + to add your first item, or ask your agent to create one for you.")
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Motivational all-done state

    /// Congratulatory view shown when the active-item list is empty because the
    /// user has completed all of their tasks for the day.
    private var motivationalState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "trophy.fill")
                .font(.system(size: Layout.trophyIconSize, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.bounce, value: completedTodayCount)
                .padding(.top, AppTheme.Spacing.xl)
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.Spacing.xs) {
                Text("You're all caught up!")
                    .font(AppTheme.Typography.title)
                    .multilineTextAlignment(.center)

                Text(motivationalSubtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
            }

            if completionStreak >= 1 {
                streakBadge
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Button(action: onAddItem) {
                    Label("Add item", systemImage: "plus")
                        .font(AppTheme.Typography.callout)
                }
                .buttonStyle(.bordered)

                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(AppTheme.Typography.callout)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.init())
    }

    private var shareText: String {
        let base = completedTodayCount == 1
            ? "I completed 1 task today"
            : "I completed \(completedTodayCount) tasks today"
        return completionStreak >= 2
            ? "\(base) — \(completionStreak) day streak! 🔥"
            : "\(base)! ✅"
    }

    private var motivationalSubtitle: String {
        switch completedTodayCount {
        case 1:
            return "1 task done today. Keep the momentum going!"
        case 2...4:
            return "\(completedTodayCount) tasks done today. You're on a roll!"
        case 5...9:
            return "\(completedTodayCount) tasks done today. Impressive work!"
        default:
            return "\(completedTodayCount) tasks done today. You're crushing it!"
        }
    }

    /// Pill badge showing the current completion streak.
    private var streakBadge: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("\(completionStreak) day streak")
                .fontWeight(.semibold)
        }
        .font(AppTheme.Typography.callout)
        .foregroundStyle(.primary)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(Color.orange.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
    }
}
