import SwiftUI

// MARK: - PlayerNavSheets

/// Pulls the two "swap the player sheet for a detail sheet" presentations
/// out of `RootView.body` so the body stays inside the Swift type-checker's
/// reasonable-time budget. Both bindings are driven by notifications posted
/// from inside the player (`PlayerClipSourceChip`, `PlayerMoreMenu`); the
/// onReceive handlers in `RootView` flip `showFullPlayer` and the matching
/// id in the same render tick so SwiftUI sees a single dismiss→present
/// transition instead of overlapping sheets.
struct PlayerNavSheets: ViewModifier {
    @Binding var episodeID: UUID?
    @Binding var subscriptionID: UUID?
    let store: AppStateStore

    func body(content: Content) -> some View {
        content
            .sheet(item: episodeBinding) { identified in
                NavigationStack {
                    EpisodeDetailView(episodeID: identified.id)
                }
            }
            .sheet(item: subscriptionBinding) { identified in
                NavigationStack {
                    if let podcast = store.podcast(id: identified.id) {
                        ShowDetailView(podcast: podcast)
                    } else {
                        ContentUnavailableView(
                            "Show not found",
                            systemImage: "questionmark.folder",
                            description: Text("This subscription is no longer in your library.")
                        )
                    }
                }
            }
    }

    private var episodeBinding: Binding<IdentifiedUUID?> {
        Binding(
            get: { episodeID.map(IdentifiedUUID.init) },
            set: { episodeID = $0?.id }
        )
    }

    private var subscriptionBinding: Binding<IdentifiedUUID?> {
        Binding(
            get: { subscriptionID.map(IdentifiedUUID.init) },
            set: { subscriptionID = $0?.id }
        )
    }

    private struct IdentifiedUUID: Identifiable {
        let id: UUID
    }
}
