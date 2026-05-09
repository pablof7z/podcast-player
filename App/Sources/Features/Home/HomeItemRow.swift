import SwiftUI

/// A single row in the Home items list.
///
/// Shows a tappable completion circle, item title, optional priority star,
/// and optional friend-request attribution. Supports a context menu and
/// swipe actions that mirror the patterns in `AgentMemoriesView`.
struct HomeItemRow: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Frame dimension of the completion circle button tap target.
        static let circleFrame: CGFloat = 36
        /// SF Symbol point size for the completion circle.
        static let circleIconSize: CGFloat = 22
        /// SF Symbol point size for the priority star and status badges.
        static let starSize: CGFloat = 13
        /// Caption font size for due-date and duration meta chips.
        static let metaCaptionFontSize: CGFloat = 11
        /// SF Symbol point size for the selection checkmark circle.
        static let selectionCircleSize: CGFloat = 22
        /// Width of the leading color stripe shown for colored items.
        static let stripeWidth: CGFloat = 3
        /// Corner radius of the leading color stripe.
        static let stripeCornerRadius: CGFloat = 2
    }

    // MARK: - Properties

    let item: Item
    /// `true` when this row is checked in bulk-edit mode.
    var isSelected: Bool = false
    /// `true` when the list is in bulk-edit mode (disables swipe, context menu, individual tap).
    var isEditMode: Bool = false
    var onTap: () -> Void
    var onToggle: () -> Void
    var onTogglePriority: () -> Void
    var onDelete: () -> Void
    /// Called when the user taps a tag chip; passes the raw tag name (without `#` prefix).
    /// When `nil`, tag chips are rendered but are not interactive.
    var onTagTap: ((String) -> Void)? = nil
    /// Called when the user selects a due-date quick-set from the context menu.
    /// Passes `nil` to clear the due date. When `nil`, the due-date submenu is omitted.
    var onSetDueDate: ((Date?) -> Void)? = nil
    /// Called when the user selects a color from the color-tag context-menu submenu.
    /// When `nil`, the color submenu is omitted.
    var onSetColorTag: ((ItemColorTag) -> Void)? = nil
    /// Called when the user taps the pin/unpin context menu action.
    /// When `nil`, the pin action is omitted from the context menu.
    var onTogglePin: (() -> Void)? = nil
    /// Called when the user selects a duration preset from the context menu.
    /// Passes `nil` to clear an existing duration. When `nil`, the duration submenu is omitted.
    var onSetDuration: ((Int?) -> Void)? = nil
    /// Called when the user selects "Duplicate" from the context menu.
    /// When `nil`, the duplicate action is omitted from the context menu.
    var onDuplicate: (() -> Void)? = nil
    /// When non-nil, the tag chip whose name matches this value is shown with a stronger
    /// background tint — used when the home view is filtered by that tag.
    var highlightedTag: String? = nil

    // MARK: - Completion animation state

    /// `true` during the brief shrink-fade animation played when the user marks a
    /// pending item done. Drives `.scaleEffect` and `.opacity` on the row content.
    /// Resets to `false` immediately if the item is re-opened (status != .done).
    @State private var isCompleting: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            colorStripe
            HStack(spacing: AppTheme.Spacing.sm) {
                if isEditMode {
                    selectionIndicator
                } else {
                    completionButton
                }
                titleStack
                Spacer(minLength: 0)
                if item.isPinned {
                    pinBadge
                }
                if item.isPriority {
                    priorityStar
                }
                if item.reminderAt != nil {
                    reminderBadge
                }
                if item.source != .manual && item.status != .done {
                    sourceBadge
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        // Completion animation: shrink and fade the row when marked done.
        .scaleEffect(isCompleting ? 0.94 : 1.0, anchor: .leading)
        .opacity(isCompleting ? 0.0 : 1.0)
        .animation(AppTheme.Animation.springFast, value: isSelected)
        .animation(AppTheme.Animation.springFast, value: item.colorTag)
        .animation(AppTheme.Animation.springFast, value: isCompleting)
        // Reset the completing state if the item is re-opened.
        .onChange(of: item.status) { _, newStatus in
            if newStatus != .done { isCompleting = false }
        }
        // Suppress swipe actions and context menu while in bulk-edit mode.
        .swipeActions(edge: .leading, allowsFullSwipe: !isEditMode) {
            if !isEditMode { prioritySwipeButton }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !isEditMode) {
            if !isEditMode {
                // Complete/reopen is the full-swipe action (first declared = leftmost revealed =
                // full-swipe target) — safe action as full-swipe mirrors Mail.app convention.
                completeSwipeButton
                deleteSwipeButton
            }
        }
        .contextMenu {
            if !isEditMode { contextMenuItems }
        }
    }

    // MARK: - Subviews

    /// A narrow vertical stripe on the leading edge that reflects the item's `colorTag`.
    /// Hidden (zero width, clear) when `colorTag == .none` so layout is unchanged for un-tagged items.
    @ViewBuilder
    private var colorStripe: some View {
        if item.colorTag != .none {
            RoundedRectangle(cornerRadius: Layout.stripeCornerRadius)
                .fill(item.colorTag.color)
                .frame(width: Layout.stripeWidth)
                .padding(.vertical, AppTheme.Spacing.xs + 2)
                .padding(.trailing, AppTheme.Spacing.xs)
                .accessibilityLabel("\(item.colorTag.label) color label")
                .accessibilityHidden(true)
        }
    }

    /// Circular selection indicator shown in bulk-edit mode instead of the completion button.
    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: Layout.selectionCircleSize))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(width: Layout.circleFrame, height: Layout.circleFrame)
            .contentShape(Rectangle())
            .symbolEffect(.bounce, value: isSelected)
    }

    private func triggerCompletionAnimation() {
        if item.status == .pending {
            withAnimation(AppTheme.Animation.springFast) { isCompleting = true }
            Task { @MainActor in
                try? await Task.sleep(for: AppTheme.Timing.completionExit)
                onToggle()
            }
        } else {
            onToggle()
        }
    }

    private var completionButton: some View {
        Button {
            triggerCompletionAnimation()
        } label: {
            Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: Layout.circleIconSize))
                .foregroundStyle(item.status == .done ? Color.accentColor : .secondary)
                .frame(width: Layout.circleFrame, height: Layout.circleFrame)
                .contentShape(Rectangle())
                // Symbol transition for the checkmark filling in.
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.status == .done ? "Mark as pending" : "Mark as done")
        .accessibilityValue(item.status == .done ? "Done" : "Pending")
        .accessibilityAddTraits(.isToggle)
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(item.title)
                .font(AppTheme.Typography.body)
                .foregroundStyle(item.status == .done ? .secondary : .primary)
                .strikethrough(item.status == .done, color: .secondary)
                .lineLimit(3)

            HStack(spacing: AppTheme.Spacing.sm) {
                if let friendName = item.requestedByDisplayName {
                    Label(friendName, systemImage: "person.fill")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if let due = item.dueAt, item.status != .done {
                    dueDateLabel(due)
                }
                if let durationLabel = item.estimatedDurationLabel, item.status != .done {
                    estimatedDurationChip(durationLabel)
                }
                if let reminder = item.reminderAt, item.status != .done {
                    reminderTimeChip(reminder)
                }
                if !item.details.isEmpty && item.status != .done {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: Layout.metaCaptionFontSize, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Has details")
                }
            }

            if !item.tags.isEmpty {
                itemTagsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var itemTagsRow: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(item.tags, id: \.self) { tag in
                tagChip(tag)
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        let isInteractive = onTagTap != nil && !isEditMode
        let isHighlighted = tag == highlightedTag
        return Text("#\(tag)")
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(isHighlighted ? Color.primary : Color.accentColor)
            .padding(.horizontal, AppTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(isHighlighted ? Color.accentColor.opacity(0.25) : Color.accentColor.opacity(0.10), in: Capsule())
            .contentShape(Rectangle())
            .onTapGesture {
                guard let onTagTap, !isEditMode else { return }
                Haptics.selection()
                onTagTap(tag)
            }
            .accessibilityLabel(isInteractive ? "Filter by tag \(tag)" : "Tag: \(tag)")
            .accessibilityAddTraits(isInteractive ? [.isButton] : [])
    }

    private func estimatedDurationChip(_ label: String) -> some View {
        Label(label, systemImage: "clock")
            .font(.system(size: Layout.metaCaptionFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private func reminderTimeChip(_ date: Date) -> some View {
        let cal = Calendar.current
        let isPast = date < Date()
        let isToday = cal.isDateInToday(date)
        let isTomorrow = cal.isDateInTomorrow(date)
        let timeStr = date.formatted(date: .omitted, time: .shortened)
        let label: String
        if isToday {
            label = timeStr
        } else if isTomorrow {
            label = "Tomorrow · \(timeStr)"
        } else if isPast {
            label = timeStr
        } else {
            label = "\(date.formatted(date: .abbreviated, time: .omitted)) · \(timeStr)"
        }
        return Label(label, systemImage: "bell.fill")
            .font(.system(size: Layout.metaCaptionFontSize, weight: .medium))
            .foregroundStyle(isPast ? Color.orange : Color.secondary)
            .labelStyle(.titleAndIcon)
    }

    private func dueDateLabel(_ date: Date) -> some View {
        let overdue = item.isOverdue
        let dueToday = !overdue && Calendar.current.isDateInToday(date)
        let label = overdue
            ? "Overdue · \(date.relativeDueLabel)"
            : "Due \(date.relativeDueLabel)"
        let icon: String
        let color: Color
        if overdue {
            icon = "clock.badge.exclamationmark.fill"
            color = .red
        } else if dueToday {
            icon = "clock.badge.fill"
            color = .orange
        } else {
            icon = "clock"
            color = .secondary
        }
        return Label(label, systemImage: icon)
            .font(.system(size: Layout.metaCaptionFontSize, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }

    private var priorityStar: some View {
        Image(systemName: "star.fill")
            .font(.system(size: Layout.starSize))
            .foregroundStyle(.orange)
            .accessibilityLabel("Priority")
    }

    private var reminderBadge: some View {
        let isRecurring = item.recurrence != .none
        return Image(systemName: isRecurring ? "arrow.clockwise.circle.fill" : "bell.fill")
            .font(.system(size: Layout.starSize))
            .foregroundStyle(isRecurring ? Color.accentColor.opacity(0.8) : .secondary)
            .accessibilityLabel(isRecurring ? "Recurring reminder (\(item.recurrence.shortLabel))" : "Reminder set")
    }

    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: Layout.starSize))
            .foregroundStyle(Color.accentColor)
            .rotationEffect(.degrees(45))
            .accessibilityLabel("Pinned")
    }

    private var sourceBadge: some View {
        Image(systemName: item.source == .agent ? "sparkles" : "mic.fill")
            .font(.system(size: Layout.starSize))
            .foregroundStyle(item.source == .agent ? Color.purple.opacity(0.7) : Color.blue.opacity(0.7))
            .accessibilityLabel(item.source == .agent ? "Added by agent" : "Added by voice")
    }

    // MARK: - Swipe actions

    private var prioritySwipeButton: some View {
        Button(action: onTogglePriority) {
            Label(
                item.isPriority ? "Remove Priority" : "Mark Priority",
                systemImage: item.isPriority ? "star.slash" : "star.fill"
            )
        }
        .tint(.orange)
    }

    /// Trailing full-swipe action: mark a pending item done (or reopen a completed one).
    ///
    /// When completing, runs the same shrink-fade exit animation as the tap-to-complete
    /// button — `isCompleting` drives both paths so behaviour is consistent.
    /// When re-opening, status flips immediately with no exit animation.
    private var completeSwipeButton: some View {
        Button {
            triggerCompletionAnimation()
        } label: {
            Label(
                item.status == .done ? "Mark as Pending" : "Mark as Done",
                systemImage: item.status == .done ? "arrow.uturn.backward.circle" : "checkmark.circle.fill"
            )
        }
        .tint(.green)
    }

    private var deleteSwipeButton: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

}
