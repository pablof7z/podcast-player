import SwiftUI

// MARK: - HomeView

struct HomeView: View {

    @Environment(AppStateStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @State var showAgentChat = false
    @State var showAddItem = false
    @State private var showCompleted = false
    @State private var showSearch = false
    @State var newItemDraft = ""
    @State var selectedItemID: UUID?
    @State var activeFilter: HomeFilter = .all
    @FocusState var addFieldFocused: Bool
    // Batch selection
    @State var isEditMode = false
    @State var selectedIDs: Set<UUID> = []
    // Undo toast
    @State var pendingUndo: UndoAction?
    // Focus-mode filter: non-nil while a configured Focus is active.
    @State var focusOverride: HomeFilter?

    // MARK: - Derived

    /// The effective filter applied to the visible-items list.
    ///
    /// When a Focus mode override is active it takes precedence over the
    /// user-selected `activeFilter`, so the list automatically narrows to the
    /// tag / style the user configured for that Focus without losing their
    /// manual selection for when Focus ends.
    var effectiveFilter: HomeFilter { focusOverride ?? activeFilter }

    var visibleItems: [Item] {
        store.filteredActiveItems(effectiveFilter)
    }

    /// Show the stats card when there is at least one active or recently-completed item.
    private var shouldShowStats: Bool {
        store.activeItems.count > 0 || store.completedTodayCount > 0
    }

    /// Show the weekly trend card when there is meaningful completion history.
    private var shouldShowWeeklyTrend: Bool {
        store.completionStreak > 0 || store.weeklyCompletions.contains(where: { $0 > 0 })
    }

    /// Heuristic suggestions derived synchronously from the item corpus.
    private var suggestions: [ItemSuggestion] {
        store.itemSuggestions
    }

    // MARK: - Progress header

    private var progressTotal: Int {
        store.completedTodayCount + store.activeItems.count
    }

    var body: some View {
        List {
            if progressTotal > 0 {
                Section {
                    HomeProgressHeader(
                        doneCount: store.completedTodayCount,
                        toGoCount: store.activeItems.count,
                        remainingMinutes: store.activeItems.reduce(0) { $0 + ($1.estimatedMinutes ?? 0) },
                        streak: store.completionStreak
                    )
                }
                .animation(AppTheme.Animation.spring, value: store.completedTodayCount)
            }

            if shouldShowStats {
                Section {
                    HomeStatsCard(
                        pendingCount: store.activeItems.count,
                        overdueCount: store.overdueItemCount,
                        completedTodayCount: store.completedTodayCount,
                        priorityCount: store.priorityItemCount,
                        dueThisWeekCount: store.dueThisWeekCount,
                        onShowCompleted: { showCompleted = true },
                        onShowOverdue: { activeFilter = .overdue; Haptics.selection() },
                        onShowDueThisWeek: { activeFilter = .dueThisWeek; Haptics.selection() }
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if shouldShowWeeklyTrend {
                        HomeWeeklyTrendCard(
                            weeklyCompletions: store.weeklyCompletions,
                            streak: store.completionStreak
                        )
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if !suggestions.isEmpty {
                        HomeSuggestionsCard(
                            suggestions: suggestions,
                            onAction: { action in
                                store.pendingHomeAction = action
                            }
                        )
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(AppTheme.Animation.spring, value: store.completedTodayCount)
                .animation(AppTheme.Animation.spring, value: store.completionStreak)
                .animation(AppTheme.Animation.spring, value: suggestions.map(\.id))
            }

            if effectiveFilter.isActive {
                filterChipRow
            }

            if showAddItem && !isEditMode {
                HomeAddItemRow(
                    draft: $newItemDraft,
                    showAddItem: $showAddItem,
                    isFocused: $addFieldFocused
                )
            }

            if visibleItems.isEmpty && !(showAddItem && !isEditMode) {
                HomeEmptyState(
                    filter: effectiveFilter,
                    focusOverride: focusOverride,
                    completedTodayCount: store.completedTodayCount,
                    completionStreak: store.completionStreak,
                    onClearFilter: { withAnimation(AppTheme.Animation.spring) { activeFilter = .all } },
                    onAddItem: { withAnimation(AppTheme.Animation.spring) { showAddItem = true } }
                )
            } else {
                itemRows
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Home")
        .toolbar {
            HomeToolbar(
                visibleItems: visibleItems,
                isEditMode: $isEditMode,
                selectedIDs: $selectedIDs,
                showCompleted: $showCompleted,
                showSearch: $showSearch,
                showAgentChat: $showAgentChat,
                showAddItem: $showAddItem,
                newItemDraft: $newItemDraft,
                onRequestAddFocus: { addFieldFocused = true },
                activeFilter: $activeFilter
            )
        }
        .animation(AppTheme.Animation.spring, value: store.activeItems.count)
        .animation(AppTheme.Animation.spring, value: activeFilter)
        .animation(AppTheme.Animation.spring, value: focusOverride)
        .animation(AppTheme.Animation.springFast, value: showAddItem)
        .animation(AppTheme.Animation.spring, value: isEditMode)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if let undo = pendingUndo {
                    HomeUndoToast(
                        action: undo,
                        onUndo: { applyUndo(undo) },
                        onDismiss: { withAnimation(AppTheme.Animation.spring) { pendingUndo = nil } }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if isEditMode && !selectedIDs.isEmpty {
                    HomeBulkActionBar(
                        selectedCount: selectedIDs.count,
                        existingTags: store.allTags,
                        onComplete: { bulkComplete() },
                        onTogglePriority: { bulkTogglePriority() },
                        onTag: { tag in bulkAddTag(tag) },
                        onSetDuration: { minutes in bulkSetDuration(minutes) },
                        onDelete: { bulkDelete() }
                    )
                }
            }
            .animation(AppTheme.Animation.spring, value: pendingUndo?.id)
        }
        .onChange(of: activeFilter) { _, _ in
            Haptics.selection()
            // Clear selection when filter changes to avoid stale cross-filter selections.
            if isEditMode { selectedIDs.removeAll() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-read the Focus filter every time the scene comes to the foreground.
            // `FocusFilterIntent.perform()` writes to shared UserDefaults; the app
            // might have been backgrounded while Focus activated, so we sync here.
            if phase == .active { applyFocusFilterIfNeeded() }
        }
        .onChange(of: store.pendingHomeAction) { _, action in
            guard let action else { return }
            store.pendingHomeAction = nil          // consume immediately — fires exactly once
            handlePendingAction(action)
        }
        .navigationDestination(isPresented: $showCompleted) {
            CompletedItemsView()
        }
        .navigationDestination(isPresented: $showSearch) {
            UniversalSearchView()
        }
        .sheet(isPresented: $showAgentChat) {
            AgentChatView()
        }
        .sheet(item: $selectedItemID) { id in
            ItemDetailSheet(itemID: id)
        }
    }

    // MARK: - Active filter chip row

    private var filterChipRow: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            // When a Focus override is active, prepend a Focus icon so the user
            // knows the filter is driven by their Focus mode, not a manual tap.
            if focusOverride != nil {
                Label("Focus", systemImage: "moon.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(Color.purple.opacity(0.12), in: Capsule())
            }

            Label(
                visibleItems.isEmpty ? effectiveFilter.label : "\(effectiveFilter.label) · \(visibleItems.count)",
                systemImage: effectiveFilter.icon
            )
            .font(AppTheme.Typography.caption)
            .foregroundStyle(effectiveFilter.chipColor)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(effectiveFilter.chipColor.opacity(0.12), in: Capsule())
            .contentTransition(.identity)

            // Only show the clear button when the filter is user-driven (not Focus).
            if focusOverride == nil {
                Button {
                    withAnimation(AppTheme.Animation.spring) {
                        activeFilter = .all
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.Typography.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }

            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: AppTheme.Spacing.xs, leading: AppTheme.Spacing.md, bottom: 0, trailing: AppTheme.Spacing.md))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
