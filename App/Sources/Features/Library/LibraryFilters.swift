import SwiftUI

// MARK: - LibraryFilter

/// Filter applied to the subscriptions grid in the Library tab.
///
/// These operate on **structured fields** (status, downloaded, transcript
/// availability) — they are *not* a search. The "ask anything" semantic
/// search lives in the Ask tab and is reached via the search-entry bar
/// at the top of `LibraryView`.
///
/// Lane 2 will replace the closure-based predicate driving these chips
/// with real subscription queries; the enum itself can stay.
enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case unplayed
    case downloaded
    case transcribed

    var id: String { rawValue }

    /// User-visible chip label. Kept short so the rail fits on iPhone SE.
    var label: String {
        switch self {
        case .all:          return "All"
        case .unplayed:     return "Unplayed"
        case .downloaded:   return "Downloaded"
        case .transcribed:  return "Transcribed"
        }
    }

    /// SF Symbol for the chip glyph. The glyph is hidden on the
    /// `.all` chip — "All" needs no decoration.
    var systemImage: String? {
        switch self {
        case .all:          return nil
        case .unplayed:     return "circle.fill"
        case .downloaded:   return "arrow.down.circle.fill"
        case .transcribed:  return "text.bubble.fill"
        }
    }
}

// MARK: - LibraryFilterChip

/// A single matte chip in the filter rail. Rendered as a capsule with
/// secondary background when inactive and the app accent tint when active.
///
/// Glass is reserved for the **rail container** (the parent), not for
/// individual chips — per the lane brief, cards-and-children are matte.
struct LibraryFilterChip: View {
    let filter: LibraryFilter
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let symbol = filter.systemImage {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.semibold))
                }
                Text(filter.label)
                    .font(AppTheme.Typography.caption)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive
                          ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(Color(.tertiarySystemFill)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func tap() {
        Haptics.selection()
        action()
    }
}

// MARK: - LibraryFilterRail

/// Horizontal scrolling rail of filter chips. The rail itself sits inside
/// a `glassSurface` container in `LibraryView` (structural glass) — this
/// view only owns the chip layout and selection bridge.
struct LibraryFilterRail: View {
    @Binding var selection: LibraryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(LibraryFilter.allCases) { filter in
                    LibraryFilterChip(
                        filter: filter,
                        isActive: selection == filter,
                        action: { withAnimation(AppTheme.Animation.springFast) {
                            selection = filter
                        } }
                    )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }
}
