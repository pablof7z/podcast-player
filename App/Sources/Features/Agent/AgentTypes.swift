import Foundation

// MARK: - AgentToolCall

/// A single tool-call request from the assistant, decoded from the LLM response.
struct AgentToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String
}

// MARK: - AgentResult

/// The accumulated result of one LLM turn: the raw assistant message dict
/// (suitable for appending directly to the `rawMessages` array) plus any
/// parsed tool calls.
struct AgentResult: @unchecked Sendable {
    let assistantMessage: [String: Any]
    let toolCalls: [AgentToolCall]
    let tokensUsed: AgentTokenUsage?

    init(
        assistantMessage: [String: Any],
        toolCalls: [AgentToolCall],
        tokensUsed: AgentTokenUsage? = nil
    ) {
        self.assistantMessage = assistantMessage
        self.toolCalls = toolCalls
        self.tokensUsed = tokensUsed
    }
}

// MARK: - AgentError

enum AgentError: LocalizedError {
    case httpError(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let detail): detail
        case .malformedResponse: "Malformed response from LLM"
        }
    }
}
