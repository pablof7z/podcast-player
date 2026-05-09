import SwiftUI

// MARK: - UndoAction

/// A reversible mutation on a single item, carried in HomeView and consumed
/// by `HomeUndoToast`. The toast shows for `displayDuration` seconds then
/// auto-dismisses; tapping "Undo" fires `perform()` to reverse the change.
struct UndoAction: Identifiable, Sendable {
    enum Kind: Sendable {
        /// Item was completed (status set to `.done`).
        case completed(itemID: UUID, title: String)
        /// Item was soft-deleted.
        case deleted(itemID: UUID, title: String)
        /// Multiple items were bulk-completed.
        case bulkCompleted(itemIDs: [UUID], count: Int)
        /// Multiple items were bulk-deleted.
        case bulkDeleted(itemIDs: [UUID], count: Int)
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind) {
        self.id = UUID()
        self.kind = kind
    }

    /// Short human-readable label for the toast message.
    var message: String {
        switch kind {
        case .completed(_, let title):
            return "\"\(title)\" completed"
        case .deleted(_, let title):
            return "\"\(title)\" deleted"
        case .bulkCompleted(_, let count):
            return "\(count) item\(count == 1 ? "" : "s") completed"
        case .bulkDeleted(_, let count):
            return "\(count) item\(count == 1 ? "" : "s") deleted"
        }
    }

    /// SF Symbol name that visually reinforces the kind of action.
    var icon: String {
        switch kind {
        case .completed, .bulkCompleted: return "checkmark.circle.fill"
        case .deleted, .bulkDeleted:     return "trash.fill"
        }
    }

    /// Color used for the leading icon.
    var iconColor: Color {
        switch kind {
        case .completed, .bulkCompleted: return .green
        case .deleted, .bulkDeleted:     return .red
        }
    }
}

// MARK: - HomeUndoToast

/// Floating banner anchored above the bottom safe-area edge.
///
/// Slides in via `.move(edge: .bottom)` when `action` is non-nil.
/// Tapping "Undo" calls `onUndo`; the auto-dismiss timer calls `onDismiss`.
/// Both callbacks should nil out the action binding to remove the toast.
struct HomeUndoToast: View {

    // MARK: - Layout constants

    private enum Layout {
        static let iconSize: CGFloat = 16
        static let toastCornerRadius: CGFloat = AppTheme.Corner.pill
        static let bottomPadding: CGFloat = 12
        static let horizontalPadding: CGFloat = AppTheme.Spacing.md
        static let verticalPadding: CGFloat = AppTheme.Spacing.sm
        /// Seconds the toast is visible before auto-dismissing.
        static let displayDuration: TimeInterval = 4
    }

    // MARK: - Inputs

    let action: UndoAction
    var onUndo: () -> Void
    var onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: action.icon)
                .font(.system(size: Layout.iconSize, weight: .semibold))
                .foregroundStyle(action.iconColor)
                .accessibilityHidden(true)

            Text(action.message)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Undo") {
                Haptics.selection()
                onUndo()
            }
            .font(AppTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .accessibilityLabel("Undo \(action.message)")
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: Layout.toastCornerRadius, style: .continuous)
        )
        .appShadow(AppTheme.Shadow.card)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.bottom, Layout.bottomPadding)
        .task(id: action.id) {
            // `.task(id:)` is cancelled automatically when the view disappears
            // or when `action.id` changes (i.e. a new undo action replaces this
            // one), so no stale timer can fire after the toast is replaced or
            // manually dismissed via the Undo button.
            try? await Task.sleep(for: .seconds(Layout.displayDuration))
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.message). Double-tap Undo to reverse.")
    }
}
