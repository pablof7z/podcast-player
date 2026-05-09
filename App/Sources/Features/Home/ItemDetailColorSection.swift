import SwiftUI

// MARK: - ItemDetailColorSection

/// Color-tag picker section rendered inside `ItemDetailSheet`.
///
/// Shows a horizontal row of color swatches (one per `ItemColorTag` case) with
/// a checkmark ring on the currently selected swatch. Mutations route through
/// `AppStateStore.setItemColorTag(_:colorTag:)` so the change is immediately
/// reflected in `HomeItemRow` without needing to save the rest of the sheet.
struct ItemDetailColorSection: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Diameter of each color swatch circle.
        static let swatchSize: CGFloat = 32
        /// Width of the selection ring border.
        static let ringWidth: CGFloat = 2.5
        /// Outer diameter of the selection ring (slightly larger than swatch).
        static let ringPadding: CGFloat = 4
        /// Extra spacing so the selection ring doesn't clip the hit target.
        static let frameOuterPadding: CGFloat = 2
        /// Point size of the slash icon on the "no color" swatch.
        static let slashIconSize: CGFloat = 14
        /// Point size of the checkmark overlay on selected swatches.
        static let checkmarkIconSize: CGFloat = 11
    }

    // MARK: - Inputs

    let item: Item

    // MARK: - Environment

    @Environment(AppStateStore.self) private var store

    // MARK: - Body

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.md) {
                    ForEach(ItemColorTag.allCases, id: \.self) { tag in
                        swatchButton(tag)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xs)
                .padding(.horizontal, AppTheme.Spacing.xs)
            }
            .listRowInsets(AppTheme.Layout.cardRowInsetsSM)
        } header: {
            Text("Color")
        } footer: {
            Text("A colored stripe appears beside the item in your list for quick visual grouping.")
        }
    }

    // MARK: - Swatch button

    private func swatchButton(_ tag: ItemColorTag) -> some View {
        let isSelected = item.colorTag == tag
        return Button {
            Haptics.selection()
            store.setItemColorTag(item.id, colorTag: tag)
        } label: {
            ZStack {
                if tag == .none {
                    // "No color" swatch: grey circle with a slash icon.
                    Circle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                    Image(systemName: "circle.slash")
                        .font(.system(size: Layout.slashIconSize, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                } else {
                    Circle()
                        .fill(tag.color)
                        .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                }

                if isSelected {
                    // Selection ring around the chosen swatch.
                    Circle()
                        .stroke(tag == .none ? Color.secondary : tag.color,
                                lineWidth: Layout.ringWidth)
                        .frame(
                            width: Layout.swatchSize + Layout.ringPadding,
                            height: Layout.swatchSize + Layout.ringPadding
                        )

                    // Checkmark overlay on non-none swatches.
                    if tag != .none {
                        Image(systemName: "checkmark")
                            .font(.system(size: Layout.checkmarkIconSize, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(
                width: Layout.swatchSize + Layout.ringPadding + Layout.frameOuterPadding,
                height: Layout.swatchSize + Layout.ringPadding + Layout.frameOuterPadding
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(tag.label), selected" : tag.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .symbolEffect(.bounce, value: isSelected)
    }
}
