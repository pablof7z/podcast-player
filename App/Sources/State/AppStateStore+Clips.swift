import Foundation

// MARK: - Clips

/// CRUD surface for user-authored transcript excerpts. Mirrors the pattern
/// used by `+Notes` and `+Memories` so all clip mutations route through one
/// place and the `state.didSet` observer in `AppStateStore` picks them up
/// for persistence + Spotlight + widget refresh.
extension AppStateStore {

    func addClip(_ clip: Clip) {
        state.clips.append(clip)
    }

    func deleteClip(id: UUID) {
        guard let idx = state.clips.firstIndex(where: { $0.id == id }) else { return }
        state.clips.remove(at: idx)
    }

    func clip(id: UUID) -> Clip? {
        state.clips.first(where: { $0.id == id })
    }

    /// Clips for a single episode, newest first. Used by the episode detail
    /// surface and (eventually) the global clips list.
    func clips(forEpisode id: UUID) -> [Clip] {
        state.clips
            .filter { $0.episodeID == id }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
