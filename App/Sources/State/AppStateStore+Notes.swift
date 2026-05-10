import Foundation

// MARK: - Notes

extension AppStateStore {

    /// User-authored note path. Defaults `author: .user` and fires a
    /// fire-and-forget kind-1 publish through `UserIdentityStore.shared`
    /// per the wiring contract in `identity-05-synthesis.md` §5.3.
    /// Existing call-sites (`AgentNotesView`, `FriendDetailView`) hit this
    /// signature unchanged.
    @discardableResult
    func addNote(text: String, kind: NoteKind = .free, target: Anchor? = nil) -> Note {
        return addNote(text: text, kind: kind, target: target, author: .user)
    }

    /// Author-aware overload. The agent-tool path passes `author: .agent`
    /// so the note is appended locally without going through publish.
    /// No `episodeID` parameter today — current call-sites have no episode
    /// anchor; the publish path passes `episodeCoord: nil` until that data
    /// flows in.
    @discardableResult
    func addNote(text: String, kind: NoteKind = .free, target: Anchor? = nil, author: NoteAuthor) -> Note {
        let note = Note(text: text, kind: kind, target: target, author: author)
        state.notes.append(note)
        if author == .user {
            // Fire-and-forget — relay outage must never block a local action.
            Task { try? await UserIdentityStore.shared.publishUserNote(note, episodeCoord: nil) }
        }
        return note
    }

    func deleteNote(_ id: UUID) {
        guard let idx = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[idx].deleted = true
    }

    func restoreNote(_ id: UUID) {
        guard let idx = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[idx].deleted = false
    }

    func updateNote(_ note: Note) {
        guard let idx = state.notes.firstIndex(where: { $0.id == note.id }) else { return }
        state.notes[idx] = note
    }

    func clearAllNotes() {
        var updated = state.notes
        for idx in updated.indices where !updated[idx].deleted {
            updated[idx].deleted = true
        }
        state.notes = updated
    }
}
