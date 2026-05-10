import SwiftUI

// MARK: - PlayerQueueSheet

/// "Up Next" sheet presented from the player's Queue chip.
///
/// Renders a SwiftUI `List` over `state.queue` (UUIDs), resolves each entry to
/// a live `Episode` via the store, and supports tap-to-play, drag-to-reorder,
/// and swipe-to-delete. Footer summarises total runtime and exposes a
/// destructive "Clear queue" action.
///
/// The queue model lives on `PlaybackState`; this view is purely
/// presentational. Adding/removing episodes elsewhere (e.g. from a list row's
/// context menu) goes through `PlaybackState.enqueue(_:)` directly.
struct PlayerQueueSheet: View {

    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: PlaybackState

    /// Drives the destructive confirmation when the user taps "Clear queue" —
    /// the queue can represent ten minutes of tap-curation, and an accidental
    /// flick on the footer button shouldn't wipe it without a beat to confirm.
    @State private var confirmClear: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if resolvedEpisodes.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear the queue?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Clear queue", role: .destructive) {
                    Haptics.warning()
                    state.clearQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(resolvedEpisodes.count) queued episodes will be removed. This cannot be undone.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Live resolution

    /// Resolve every queue UUID to a live `Episode`. Drops any entry whose
    /// episode no longer exists in the store (e.g. user unsubscribed mid-play)
    /// rather than rendering a "missing" row — the UI surface for a stale
    /// queue entry would just be confusing.
    private var resolvedEpisodes: [Episode] {
        state.queue.compactMap { store.episode(id: $0) }
    }

    private var totalRuntime: TimeInterval {
        resolvedEpisodes.reduce(0) { acc, ep in
            acc + (ep.duration ?? 0)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing queued",
            systemImage: "list.bullet.rectangle",
            description: Text("Episodes you queue from the library will appear here.")
        )
    }

    // MARK: - List

    private var queueList: some View {
        List {
            Section {
                ForEach(resolvedEpisodes) { episode in
                    // Wrapped in a `Button` (not `.onTapGesture`) because
                    // SwiftUI's always-active edit mode can swallow tap
                    // gestures on the trailing edge where the move handle
                    // sits. `Button` reliably hits the whole row.
                    Button {
                        play(episode)
                    } label: {
                        PlayerQueueRow(
                            episode: episode,
                            showName: store.subscription(id: episode.subscriptionID)?.title ?? "",
                            showImageURL: store.subscription(id: episode.subscriptionID)?.imageURL
                        )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Subtle row tint so the standard reorder chevrons
                    // (rendered by always-active edit mode) read against the
                    // sheet's grouped background. Without this the trailing
                    // handles are nearly invisible against the row fill in
                    // dark mode.
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    // Custom destructive label — `.onDelete` would render
                    // "Delete", which suggests irreversibility. "Remove" matches
                    // queue semantics: the episode stays in the library, it's
                    // only being pulled from Up Next. This `.swipeActions`
                    // label is also what edit-mode's inline red-minus confirm
                    // surfaces, so the affordance is consistent.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            removeFromQueue(episode.id)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
                .onMove { indices, destination in
                    state.moveQueue(from: indices, to: destination)
                    Haptics.selection()
                }
            } footer: {
                footer
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(runtimeSummary)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)

            // Two-step confirm — the actual clear lives in the
            // `.confirmationDialog` attached to the `NavigationStack`. Tapping
            // here just arms the dialog; that protects against the user flicking
            // the footer accidentally while reordering.
            Button(role: .destructive) {
                Haptics.selection()
                confirmClear = true
            } label: {
                Label("Clear queue", systemImage: "trash")
                    .font(AppTheme.Typography.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    private var runtimeSummary: String {
        let count = resolvedEpisodes.count
        let runtime = PlayerTimeFormat.clock(totalRuntime)
        let plural = count == 1 ? "episode" : "episodes"
        return "\(count) \(plural) • \(runtime)"
    }

    // MARK: - Actions

    private func play(_ episode: Episode) {
        Haptics.medium()
        state.removeFromQueue(episode.id)
        state.setEpisode(episode)
        state.play()
        dismiss()
    }

    private func removeFromQueue(_ id: UUID) {
        state.removeFromQueue(id)
        Haptics.light()
    }
}

// MARK: - PlayerQueueRow

/// Row used inside `PlayerQueueSheet`. Pulled out so the parent stays under
/// the soft line limit and the row gets its own preview surface as the
/// design lane iterates on it.
struct PlayerQueueRow: View {

    let episode: Episode
    let showName: String
    /// Show-level cover art used as a fallback when the episode has no
    /// per-episode `<itunes:image>`. Most feeds only ship show-level
    /// artwork; without this fallback the row would render a generic
    /// waveform glyph for those episodes.
    var showImageURL: URL? = nil

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                if !showName.isEmpty {
                    Text(showName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(episode.title)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let runtime = formattedRuntime {
                    Text(runtime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var artwork: some View {
        Group {
            if let url = episode.imageURL ?? showImageURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
            )
    }

    private var formattedRuntime: String? {
        guard let duration = episode.duration, duration > 0 else { return nil }
        return PlayerTimeFormat.clock(duration)
    }
}
