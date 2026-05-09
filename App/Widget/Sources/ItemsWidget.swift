import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ItemsEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
    /// Up to 3 priority items for the medium widget.
    let priorityItems: [WidgetItem]
    /// Up to 5 next pending items (non-priority) for the medium widget.
    let nextItems: [WidgetItem]
}

private extension ItemsEntry {
    static var placeholder: ItemsEntry {
        ItemsEntry(
            date: Date(),
            pendingCount: 5,
            priorityItems: [
                WidgetItem.preview("Review project plan", priority: true),
                WidgetItem.preview("Send weekly update", priority: true),
            ],
            nextItems: [
                WidgetItem.preview("Schedule 1:1 with team", priority: false),
                WidgetItem.preview("Update documentation", priority: false),
            ]
        )
    }
}

// MARK: - Timeline provider

struct ItemsWidgetProvider: TimelineProvider {
    typealias Entry = ItemsEntry

    func placeholder(in context: Context) -> ItemsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ItemsEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ItemsEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 15 minutes; the app can call WidgetCenter.shared.reloadAllTimelines()
        // on any state mutation to get near-instant updates.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> ItemsEntry {
        let state = WidgetPersistence.loadState()
        // Use sortedPendingItems so the widget honors the user's drag-to-reorder
        // order (within each priority group) rather than raw insertion order.
        let sorted = state.sortedPendingItems
        let priority = sorted.filter(\.isPriority).prefix(WidgetTheme.Layout.maxPriorityItems).map { $0 }
        let next = sorted.filter { !$0.isPriority }.prefix(WidgetTheme.Layout.maxNextItems).map { $0 }
        return ItemsEntry(
            date: Date(),
            pendingCount: sorted.count,
            priorityItems: priority,
            nextItems: next
        )
    }
}

// MARK: - Small widget view

/// System small (2×2): shows the pending item count with a contextual subtitle.
private struct SmallWidgetView: View {
    let entry: ItemsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetTheme.Layout.smallVSpacing) {
            Image(systemName: "checklist")
                .font(WidgetTheme.Typography.smallIcon)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Text("\(entry.pendingCount)")
                .font(WidgetTheme.Typography.smallCount)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(entry.pendingCount == 1 ? "item pending" : "items pending")
                .font(WidgetTheme.Typography.smallSubtitle)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetTheme.Spacing.pad)
        .background(WidgetTheme.Colors.brandGradient)
    }
}

// MARK: - Medium widget view

/// System medium (4×2): shows a prioritized list of pending items.
private struct MediumWidgetView: View {
    let entry: ItemsEntry

    private var displayItems: [WidgetItem] {
        // Lead with priority items, then fill with next items, cap at 4 rows.
        let combined = entry.priorityItems + entry.nextItems
        return Array(combined.prefix(WidgetTheme.Layout.mediumMaxRows))
    }

    var body: some View {
        if displayItems.isEmpty {
            emptyView
        } else {
            itemsView
        }
    }

    private var emptyView: some View {
        VStack(spacing: WidgetTheme.Spacing.emptyStateSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .font(WidgetTheme.Typography.emptyIcon)
                .foregroundStyle(.green)
            Text("All clear!")
                .font(WidgetTheme.Typography.emptyTitle)
            Text("No pending items")
                .font(WidgetTheme.Typography.emptySubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WidgetTheme.Spacing.pad)
    }

    private var itemsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: WidgetTheme.Layout.headerIconSpacing) {
                Image(systemName: "checklist")
                    .font(WidgetTheme.Typography.header)
                    .foregroundStyle(WidgetTheme.Colors.brandIndigo)
                Text("\(entry.pendingCount) pending")
                    .font(WidgetTheme.Typography.header)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, WidgetTheme.Spacing.pad)
            .padding(.top, WidgetTheme.Spacing.headerTop)
            .padding(.bottom, WidgetTheme.Spacing.headerBottom)

            // Item rows
            ForEach(displayItems) { item in
                itemRow(item)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func itemRow(_ item: WidgetItem) -> some View {
        HStack(spacing: WidgetTheme.Spacing.rowIconGap) {
            Circle()
                .strokeBorder(
                    item.isPriority ? Color.orange : WidgetTheme.Colors.itemCircleStroke,
                    lineWidth: WidgetTheme.Layout.itemCircleStrokeWidth
                )
                .frame(
                    width: WidgetTheme.Layout.itemCircleSize,
                    height: WidgetTheme.Layout.itemCircleSize
                )

            Text(item.title)
                .font(WidgetTheme.Typography.itemTitle)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if item.isPriority {
                Image(systemName: "star.fill")
                    .font(WidgetTheme.Typography.starIcon)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, WidgetTheme.Spacing.pad)
        .padding(.vertical, WidgetTheme.Spacing.rowVertical)
    }
}

// MARK: - Accessory widget view (lock screen)

/// Accessory circular (lock screen): shows pending count.
private struct AccessoryCircularView: View {
    let entry: ItemsEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(entry.pendingCount)")
                    .font(WidgetTheme.Typography.accessoryCount)
                    .minimumScaleFactor(0.6)
                Image(systemName: "checklist")
                    .font(WidgetTheme.Typography.accessoryIcon)
            }
        }
    }
}

/// Accessory rectangular (lock screen): shows up to 2 top items.
private struct AccessoryRectangularView: View {
    let entry: ItemsEntry

    private var topItems: [WidgetItem] {
        let all = entry.priorityItems + entry.nextItems
        return Array(all.prefix(WidgetTheme.Layout.accessoryMaxRows))
    }

    var body: some View {
        if topItems.isEmpty {
            Label("All clear", systemImage: "checkmark.circle.fill")
                .font(WidgetTheme.Typography.accessoryLabel)
        } else {
            VStack(alignment: .leading, spacing: WidgetTheme.Spacing.accessoryRowSpacing) {
                ForEach(topItems) { item in
                    Label {
                        Text(item.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: item.isPriority ? "star.fill" : "circle")
                    }
                    .font(WidgetTheme.Typography.accessoryRow)
                }
            }
        }
    }
}

// MARK: - Widget configuration

/// Items widget — shows pending task count and top items across system small,
/// medium, accessory circular, and accessory rectangular sizes.
struct ItemsWidget: Widget {
    let kind: String = "ItemsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ItemsWidgetProvider()) { entry in
            ItemsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Items")
        .description("See your pending items at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct ItemsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ItemsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}
