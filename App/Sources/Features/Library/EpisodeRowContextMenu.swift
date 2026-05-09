import SwiftUI

// MARK: - EpisodeRowContextMenu

/// Shared "long-press menu" for any episode row in the app.
///
/// Surfaces:
///   - Open episode details (NavigationLink with a caller-supplied route value).
///   - Mark as played / Mark as unplayed (toggle based on `episode.played`).
///   - Download / Cancel download / Remove download / Retry download
///     (state-aware via `EpisodeDownloadService.shared`).
///   - Share (`ShareLink` with the enclosure URL).
///
/// The route is generic over `Hashable` so Library can pass `LibraryEpisodeRoute`
/// and Home can pass `HomeEpisodeRoute` without either feature owning the menu.
///
/// Usage with `.contextMenu`:
/// ```swift
/// .contextMenu {
///     EpisodeRowContextMenu(
///         episode: ep,
///         store: store,
///         openDetailsRoute: LibraryEpisodeRoute(...)
///     )
/// }
/// ```
///
/// Usage with `.accessibilityActions` (mirror the same items so VoiceOver
/// users get the same affordances — see `episodeRowAccessibilityActions`):
struct EpisodeRowContextMenu<Route: Hashable>: View {
    let episode: Episode
    let store: AppStateStore
    let openDetailsRoute: Route

    /// Live download service — observed so the surfaced affordance flips between
    /// Download / Cancel / Remove / Retry as the underlying state moves.
    @State private var downloadService = EpisodeDownloadService.shared

    var body: some View {
        // No wrapping container view — `.contextMenu` walks the body looking
        // for menu items (Buttons / NavigationLinks / ShareLinks). A `Group`
        // works for content but any modifier attached to it (e.g. a
        // `.confirmationDialog`) would orphan because the Group isn't part of
        // the visible hierarchy. Keep the body item-only.
        NavigationLink(value: openDetailsRoute) {
            Label("Open episode details", systemImage: "info.circle")
        }

        Button {
            togglePlayed()
        } label: {
            Label(
                episode.played ? "Mark as unplayed" : "Mark as played",
                systemImage: episode.played ? "circle" : "checkmark.circle"
            )
        }

        downloadButton

        ShareLink(item: episode.enclosureURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - Download affordance

    @ViewBuilder
    private var downloadButton: some View {
        switch episode.downloadState {
        case .notDownloaded, .queued:
            Button {
                Haptics.light()
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.download(episodeID: episode.id)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Button {
                Haptics.light()
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.cancel(episodeID: episode.id)
            } label: {
                Label("Cancel download", systemImage: "xmark.circle")
            }
        case .downloaded:
            // Match the trailing-swipe behavior — remove immediately. The
            // detail view's `EpisodeDetailActionsMenu` keeps the confirmation
            // dialog because it's hosted on a real `Menu` parent. Inside
            // `.contextMenu` the dialog modifier orphans (the menu items don't
            // land in the visible hierarchy), so we drop it here for parity.
            Button(role: .destructive) {
                Haptics.warning()
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.delete(episodeID: episode.id)
            } label: {
                Label("Remove download", systemImage: "trash")
            }
        case .failed:
            Button {
                Haptics.light()
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.download(episodeID: episode.id)
            } label: {
                Label("Retry download", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Mutations

    private func togglePlayed() {
        if episode.played {
            Haptics.itemReopen()
            store.markEpisodeUnplayed(episode.id)
        } else {
            Haptics.itemComplete()
            store.markEpisodePlayed(episode.id)
        }
    }
}

// MARK: - Accessibility-action mirror

/// `.accessibilityActions` builder that mirrors `EpisodeRowContextMenu` so
/// VoiceOver users get the same options the long-press menu surfaces. Kept
/// in this file so the menu and the custom-actions stay in lockstep when one
/// changes — divergence is the failure mode the brief flagged.
///
/// Note: `accessibilityActions` cannot host a `NavigationLink`, so the
/// "Open episode details" affordance is delegated to a closure the caller
/// wires up via the route binding. We deliberately omit the share affordance
/// here — `ShareLink` does not surface reliably as a VoiceOver custom action
/// (UIActivityViewController presentation from a custom-action context fails
/// silently). The long-press menu retains Share for sighted users.
struct EpisodeRowAccessibilityActions: View {
    let episode: Episode
    let store: AppStateStore
    let onOpenDetails: () -> Void

    var body: some View {
        Button("Open episode details") { onOpenDetails() }
        Button(episode.played ? "Mark as unplayed" : "Mark as played") {
            togglePlayed()
        }
        downloadAction
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch episode.downloadState {
        case .notDownloaded, .queued:
            Button("Download") {
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.download(episodeID: episode.id)
            }
        case .downloading:
            Button("Cancel download") {
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.cancel(episodeID: episode.id)
            }
        case .downloaded:
            Button("Remove download") {
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.delete(episodeID: episode.id)
            }
        case .failed:
            Button("Retry download") {
                EpisodeDownloadService.shared.attach(appStore: store)
                EpisodeDownloadService.shared.download(episodeID: episode.id)
            }
        }
    }

    private func togglePlayed() {
        if episode.played {
            store.markEpisodeUnplayed(episode.id)
        } else {
            store.markEpisodePlayed(episode.id)
        }
    }
}

// MARK: - Swipe-action helpers

/// Leading-edge swipe action: "Add to Queue".
///
/// Appends the episode to `PlaybackState.queue` so it's picked up by the
/// "Up Next" rail. No-op (silently absorbed by `PlaybackState.enqueue`)
/// when the episode is already queued or is the currently-playing item —
/// the swipe still resolves visually so the user gets affordance feedback.
///
/// Apply via `.swipeActions(edge: .leading, allowsFullSwipe: true) { ... }`
/// on a `List` row — the enclosing call site decides where this lives so
/// non-`List` surfaces (the Home rail card) can opt out cleanly. The
/// download / mark-played affordances that previously lived on the swipe
/// edges are still available via `EpisodeRowContextMenu` (long-press).
struct EpisodeRowLeadingSwipeAction: View {
    let episode: Episode
    let playback: PlaybackState

    var body: some View {
        Button {
            Haptics.success()
            playback.enqueue(episode.id)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        .tint(.indigo)
    }
}

/// Trailing-edge swipe action: destructive "Remove" — drops the episode
/// from the visible list.
///
/// "Remove from list" semantically means "treat as done": calling
/// `markEpisodePlayed` removes the episode from `recentEpisodes`
/// (filters on `!played`) and from `inProgressEpisodes`, which is what
/// the user actually wants when they swipe away an item they're not
/// going to listen to. The download / mark-unplayed affordances remain
/// available via `EpisodeRowContextMenu` (long-press).
struct EpisodeRowTrailingSwipeAction: View {
    let episode: Episode
    let store: AppStateStore

    var body: some View {
        Button(role: .destructive) {
            Haptics.warning()
            store.markEpisodePlayed(episode.id)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}
