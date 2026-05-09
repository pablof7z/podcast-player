import Foundation

// MARK: - Notes

extension AppStateStore {

    @discardableResult
    func addNote(text: String, kind: NoteKind = .free, target: Anchor? = nil) -> Note {
        let note = Note(text: text, kind: kind, target: target)
        state.notes.append(note)
        SpotlightIndexer.reindex(state: state)
        return note
    }

    func deleteNote(_ id: UUID) {
        guard let idx = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[idx].deleted = true
        SpotlightIndexer.reindex(state: state)
    }

    func restoreNote(_ id: UUID) {
        guard let idx = state.notes.firstIndex(where: { $0.id == id }) else { return }
        state.notes[idx].deleted = false
        SpotlightIndexer.reindex(state: state)
    }

    func updateNote(_ note: Note) {
        guard let idx = state.notes.firstIndex(where: { $0.id == note.id }) else { return }
        state.notes[idx] = note
        SpotlightIndexer.reindex(state: state)
    }

    func clearAllNotes() {
        var updated = state.notes
        for idx in updated.indices where !updated[idx].deleted {
            updated[idx].deleted = true
        }
        state.notes = updated
        SpotlightIndexer.reindex(state: state)
    }
}
