import Foundation

extension AgentTools {

    @MainActor
    static func dispatchNotesMemory(
        name: String,
        args: [String: Any],
        store: AppStateStore,
        batchID: UUID
    ) -> String {
        switch name {
        case Names.createNote:
            return createNote(args: args, store: store, batchID: batchID)
        case Names.recordMemory:
            return recordMemory(args: args, store: store, batchID: batchID)
        default:
            logger.warning("No template tool is registered for '\(name, privacy: .public)'")
            return toolError("Unknown tool: \(name)")
        }
    }

    @MainActor
    private static func createNote(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let text = (args["text"] as? String)?.trimmed, !text.isEmpty else {
            return toolError("Missing note text")
        }

        let kind: NoteKind = (args["kind"] as? String) == "reflection" ? .reflection : .free
        // Agent-authored: takes the no-publish branch in `addNote(...)` per
        // `identity-05-synthesis.md` §5.3.
        let note = store.addNote(text: text, kind: kind, author: .agent)
        store.recordAgentActivity(
            AgentActivityEntry(
                batchID: batchID,
                kind: .noteCreated(noteID: note.id),
                summary: "Saved note \"\(truncated(text))\""
            )
        )
        return toolSuccess(["id": note.id.uuidString, "summary": "Saved note"])
    }

    @MainActor
    private static func recordMemory(args: [String: Any], store: AppStateStore, batchID: UUID) -> String {
        guard let content = (args["content"] as? String)?.trimmed, !content.isEmpty else {
            return toolError("Missing memory content")
        }

        let memory = store.addAgentMemory(content: content)
        store.recordAgentActivity(
            AgentActivityEntry(
                batchID: batchID,
                kind: .memoryRecorded(memoryID: memory.id),
                summary: "Remembered \"\(truncated(content))\""
            )
        )
        return toolSuccess(["id": memory.id.uuidString, "summary": "Saved memory"])
    }
}
