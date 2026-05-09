import SwiftUI

// MARK: - ItemSuggestion

/// A heuristic suggestion surfaced in the home list to prompt the user to act.
struct ItemSuggestion: Identifiable, Equatable {
    let id: UUID
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: HomeAction

    static func == (lhs: ItemSuggestion, rhs: ItemSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - HomeSuggestionsCard

/// A compact card in the home list showing one or more actionable suggestions.
struct HomeSuggestionsCard: View {

    private enum Layout {
        static let iconSize: CGFloat = 14
        static let chevronSize: CGFloat = 12
    }

    let suggestions: [ItemSuggestion]
    let onAction: (HomeAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                suggestionRow(suggestion)
                if suggestion.id != suggestions.last?.id {
                    Divider().padding(.leading, AppTheme.Layout.iconSm + AppTheme.Spacing.sm)
                }
            }
        }
        .glassSurface(cornerRadius: AppTheme.Corner.lg)
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func suggestionRow(_ suggestion: ItemSuggestion) -> some View {
        Button {
            onAction(suggestion.action)
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .foregroundStyle(suggestion.color)
                    .frame(width: AppTheme.Layout.iconSm, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(.primary)
                    Text(suggestion.subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: Layout.chevronSize, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}
