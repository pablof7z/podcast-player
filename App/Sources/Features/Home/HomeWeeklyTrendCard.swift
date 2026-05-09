import SwiftUI

// MARK: - HomeWeeklyTrendCard

/// A compact card showing a 7-day completion bar chart and the current streak.
///
/// Sits below `HomeStatsCard` in the Home list and is visible whenever there
/// is at least one completion in the past seven days (or a non-zero streak).
struct HomeWeeklyTrendCard: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Height of the bar-chart area (excludes day-label row).
        static let barAreaHeight: CGFloat = 44
        /// Minimum bar height so even a zero-count day shows a nub.
        static let barMinHeight: CGFloat = 4
        /// Width of each day bar.
        static let barWidth: CGFloat = 20
        /// Point size of the flame icon in the streak cell.
        static let flameIconSize: CGFloat = 16
        /// Divider height between the streak cell and bar chart cell.
        static let dividerHeight: CGFloat = 32
        /// Point size of the day-of-week letter beneath each bar.
        static let dayLabelFontSize: CGFloat = 9
        /// Spacing between a bar and its day letter.
        static let barLabelSpacing: CGFloat = 2
        /// Point size of the count badge shown above today's bar.
        static let todayCountFontSize: CGFloat = 9
    }

    // MARK: - Inputs

    /// Completion counts for the last 7 days, oldest first (index 0 = 6 days ago).
    let weeklyCompletions: [Int]
    /// Number of consecutive days with at least one completion.
    let streak: Int

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            streakCell
            Divider()
                .frame(height: Layout.dividerHeight)
            barChartCell
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: AppTheme.Corner.lg)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    // MARK: - Streak cell

    private var streakCell: some View {
        VStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: Layout.flameIconSize, weight: .medium))
                    .foregroundStyle(streak > 0 ? .orange : .secondary)
                    .symbolEffect(.bounce, value: streak)
                    .accessibilityHidden(true)
                if streak > 0 {
                    Text("\(streak)")
                        .font(AppTheme.Typography.title3)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            Text(streak == 0 ? "no streak yet" : streak == 1 ? "day streak" : "days streak")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    // MARK: - Bar chart cell

    private var weeklyTotal: Int { weeklyCompletions.reduce(0, +) }

    private var barChartCell: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            bars
            Text(weeklyTotal == 1 ? "1 done this week" : "\(weeklyTotal) done this week")
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var bars: some View {
        let maxCount = max(weeklyCompletions.max() ?? 1, 1)
        let letters = Self.dayLetters()
        return HStack(alignment: .bottom, spacing: AppTheme.Spacing.xs) {
            ForEach(Array(weeklyCompletions.enumerated()), id: \.offset) { index, count in
                let isToday = index == 6
                VStack(spacing: Layout.barLabelSpacing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: Layout.todayCountFontSize,
                                          weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                            .monospacedDigit()
                            .frame(width: Layout.barWidth)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        Color.clear
                            .frame(width: Layout.barWidth, height: Layout.todayCountFontSize)
                    }
                    barView(count: count, maxCount: maxCount, isToday: isToday)
                    Text(letters[index])
                        .font(.system(size: Layout.dayLabelFontSize,
                                      weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(width: Layout.barWidth)
                }
            }
        }
        .frame(height: Layout.barAreaHeight)
    }

    private func barView(count: Int, maxCount: Int, isToday: Bool) -> some View {
        let ratio = count == 0 ? 0 : max(Double(count) / Double(maxCount), 0)
        let height = Layout.barMinHeight
            + ratio * (Layout.barAreaHeight - Layout.barMinHeight)
        return Capsule()
            .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.35))
            .frame(width: Layout.barWidth, height: max(height, Layout.barMinHeight))
            .animation(AppTheme.Animation.spring, value: count)
    }

    // MARK: - Day-of-week labels

    /// Returns single-character weekday symbols for the last 7 days, oldest first.
    /// Uses the locale's `veryShortWeekdaySymbols` (e.g. "S", "M", "T"…).
    private static func dayLetters() -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let symbols = cal.veryShortWeekdaySymbols
        return (0..<7).map { i -> String in
            guard let day = cal.date(byAdding: .day, value: i - 6, to: today) else { return "" }
            let weekday = cal.component(.weekday, from: day) - 1
            return symbols[weekday]
        }
    }
}
