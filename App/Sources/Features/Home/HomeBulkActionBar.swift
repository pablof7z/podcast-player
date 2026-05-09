import SwiftUI

// MARK: - HomeBulkActionBar

/// Floating bottom bar shown in HomeView when one or more items are selected
/// during bulk-edit mode.
///
/// Offers five operations:
/// - **Complete** — marks all selected items done.
/// - **Priority** — toggles the priority flag on all selected items.
/// - **Tag** — opens a picker to add a tag to all selected items.
/// - **Time** — opens a picker to set an estimated duration on all selected items.
/// - **Delete** — asks for confirmation, then deletes.
///
/// The bar is rendered inside an `.overlay(alignment: .bottom)` so it floats
/// above the list without pushing content up.
struct HomeBulkActionBar: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Minimum height for the action bar's tap targets.
        static let buttonMinHeight: CGFloat = 44
        /// Corner radius of the floating action bar background pill.
        static let barCornerRadius: CGFloat = AppTheme.Corner.xl
        /// Vertical padding inside the action bar.
        static let barPaddingV: CGFloat = AppTheme.Spacing.sm
        /// Horizontal padding inside the action bar.
        static let barPaddingH: CGFloat = AppTheme.Spacing.md
        /// Point size of action icons.
        static let iconSize: CGFloat = 17
    }

    // MARK: - Input

    let selectedCount: Int
    /// All existing tags in the store — presented in the tag picker for quick selection.
    var existingTags: [String] = []
    var onComplete: () -> Void
    var onTogglePriority: () -> Void
    /// Called with the chosen tag name (already trimmed/lowercased) when the user
    /// picks or types a tag. `nil` is never passed — the caller must normalize.
    var onTag: (String) -> Void
    /// Called with the chosen duration in minutes, or `nil` to clear the estimate.
    var onSetDuration: (Int?) -> Void
    var onDelete: () -> Void

    // MARK: - State

    @State private var showDeleteConfirm = false
    @State private var showTagPicker = false
    @State private var showDurationPicker = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            bar
        }
        .ignoresSafeArea(edges: .bottom)
        .alert(deleteAlertTitle, isPresented: $showDeleteConfirm, actions: deleteAlertActions, message: deleteAlertMessage)
        .sheet(isPresented: $showTagPicker) {
            BulkTagPickerSheet(
                existingTags: existingTags,
                onSelect: { tag in
                    showTagPicker = false
                    onTag(tag)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDurationPicker) {
            BulkDurationPickerSheet(
                onSelect: { minutes in
                    showDurationPicker = false
                    onSetDuration(minutes)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 0) {
            actionButton(
                title: "Complete",
                icon: "checkmark.circle.fill",
                tint: .green,
                action: onComplete
            )
            Divider()
                .frame(height: Layout.buttonMinHeight * 0.6)
            actionButton(
                title: "Priority",
                icon: "star.fill",
                tint: .orange,
                action: onTogglePriority
            )
            Divider()
                .frame(height: Layout.buttonMinHeight * 0.6)
            actionButton(
                title: "Tag",
                icon: "tag.fill",
                tint: .accentColor,
                action: { showTagPicker = true }
            )
            Divider()
                .frame(height: Layout.buttonMinHeight * 0.6)
            actionButton(
                title: "Time",
                icon: "clock.fill",
                tint: .teal,
                action: { showDurationPicker = true }
            )
            Divider()
                .frame(height: Layout.buttonMinHeight * 0.6)
            actionButton(
                title: "Delete",
                icon: "trash.fill",
                tint: .red,
                action: { showDeleteConfirm = true }
            )
        }
        .padding(.horizontal, Layout.barPaddingH)
        .padding(.vertical, Layout.barPaddingV)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.barCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.barCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.Tint.hairline, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.lg)
        .appShadow(AppTheme.Shadow.lifted)
    }

    // MARK: - Action button

    private func actionButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.buttonMinHeight)
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Delete confirmation

    private var deleteAlertTitle: String {
        selectedCount == 1 ? "Delete Item?" : "Delete \(selectedCount) Items?"
    }

    @ViewBuilder
    private func deleteAlertActions() -> some View {
        Button("Delete", role: .destructive, action: onDelete)
        Button("Cancel", role: .cancel) {}
    }

    private func deleteAlertMessage() -> some View {
        Text("This permanently removes the selected \(selectedCount == 1 ? "item" : "items").")
    }
}

// MARK: - HomeBulkSelectionBar

/// Compact inline toolbar shown while edit mode is active, replacing the normal
/// trailing toolbar buttons. Lets the user select or deselect all items at once
/// and shows the current selection count.
struct HomeBulkSelectionBar: View {

    let totalCount: Int
    let selectedCount: Int
    var onSelectAll: () -> Void
    var onDeselectAll: () -> Void

    private var allSelected: Bool { selectedCount == totalCount && totalCount > 0 }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            countLabel
            Spacer(minLength: AppTheme.Spacing.xs)
            selectAllButton
        }
    }

    private var countLabel: some View {
        Text(selectedCount == 0 ? "Select items" : "\(selectedCount) selected")
            .font(AppTheme.Typography.callout)
            .foregroundStyle(selectedCount == 0 ? .secondary : .primary)
            .contentTransition(.numericText())
            .animation(AppTheme.Animation.springFast, value: selectedCount)
    }

    private var selectAllButton: some View {
        Button {
            Haptics.selection()
            if allSelected { onDeselectAll() } else { onSelectAll() }
        } label: {
            Text(allSelected ? "Deselect All" : "Select All")
                .font(AppTheme.Typography.callout)
        }
    }
}
