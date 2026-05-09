import SwiftUI

// MARK: - EpisodeDetailActionsMenu

/// Trailing toolbar menu shown by `EpisodeDetailView`: download / mark-played
/// toggles. Routes every mutation through `AppStateStore` so the change
/// persists immediately and propagates to the rest of the app.
///
/// The download toggle synthesizes a sentinel local-file URL because the
/// download manager itself lives in another lane. Once that lane lands the
/// `toggleDownload` body is the one place to swap.
struct EpisodeDetailActionsMenu: View {
    let episode: Episode
    let store: AppStateStore

    var body: some View {
        Menu {
            Button {
                toggleDownload()
            } label: {
                Label(isDownloaded ? "Remove download" : "Download",
                      systemImage: isDownloaded ? "trash" : "arrow.down.circle")
            }
            Button {
                togglePlayed()
            } label: {
                Label(episode.played ? "Mark as unplayed" : "Mark as played",
                      systemImage: episode.played ? "circle" : "checkmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("Episode options")
    }

    private var isDownloaded: Bool {
        if case .downloaded = episode.downloadState { return true }
        return false
    }

    private func toggleDownload() {
        if isDownloaded {
            store.setEpisodeDownloadState(episode.id, state: .notDownloaded)
        } else {
            let sentinel = URL(fileURLWithPath: "/dev/null")
            store.setEpisodeDownloadState(
                episode.id,
                state: .downloaded(localFileURL: sentinel, byteCount: 0)
            )
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
