import Foundation

// MARK: - Agent Memories

extension AppStateStore {

    @discardableResult
    func addAgentMemory(content: String) -> AgentMemory {
        let memory = AgentMemory(content: content)
        state.agentMemories.append(memory)
        SpotlightIndexer.reindex(state: state)
        return memory
    }

    func updateAgentMemory(_ id: UUID, content: String) {
        guard let idx = state.agentMemories.firstIndex(where: { $0.id == id }) else { return }
        state.agentMemories[idx].content = content
        SpotlightIndexer.reindex(state: state)
    }

    func deleteAgentMemory(_ id: UUID) {
        guard let idx = state.agentMemories.firstIndex(where: { $0.id == id }) else { return }
        state.agentMemories[idx].deleted = true
        SpotlightIndexer.reindex(state: state)
    }

    func restoreAgentMemory(_ id: UUID) {
        guard let idx = state.agentMemories.firstIndex(where: { $0.id == id }) else { return }
        state.agentMemories[idx].deleted = false
        SpotlightIndexer.reindex(state: state)
    }

    func clearAllAgentMemories() {
        var updated = state.agentMemories
        for idx in updated.indices where !updated[idx].deleted {
            updated[idx].deleted = true
        }
        state.agentMemories = updated
        SpotlightIndexer.reindex(state: state)
    }

    var activeMemories: [AgentMemory] {
        state.agentMemories.filter { !$0.deleted }
    }
}
