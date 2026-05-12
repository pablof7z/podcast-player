import Foundation

// MARK: - JSON Schema (OpenAI tool format)

extension AgentTools {
    /// OpenAI-compatible tool schema array, ready to embed in a chat-completions request.
    @MainActor
    static var schema: [[String: Any]] {
        [
            tool(
                name: Names.createNote,
                description: "Save a note or reflection.",
                properties: [
                    "text": ["type": "string", "description": "Note content"],
                    "kind": ["type": "string", "enum": ["free", "reflection"], "description": "Note type"],
                ],
                required: ["text"]
            ),
            tool(
                name: Names.recordMemory,
                description: "Save something important to remember about the user for future sessions.",
                properties: ["content": ["type": "string", "description": "The fact to remember"]],
                required: ["content"]
            ),
            tool(
                name: Names.upgradeThinking,
                description: "Switch the agent to a stronger reasoning model for the rest of this conversation. Call this BEFORE answering when the task needs multi-step reasoning, planning, writing code, careful synthesis, or you are unsure. Do NOT call for simple lookups, single-tool answers, or short factual replies. Idempotent — calling again is harmless.",
                properties: [
                    "reason": [
                        "type": "string",
                        "description": "One short sentence explaining why the stronger model is needed.",
                    ],
                ],
                required: []
            ),
            tool(
                name: Names.useSkill,
                description: "Opt this conversation into a skill listed under '## Skills' in the system prompt. The tool result returns the skill's manual (focused instructions you should follow for the remainder of the conversation) and unlocks the skill's tools. Idempotent — re-calling is harmless. Call this BEFORE the first call to any skill-gated tool.",
                properties: [
                    "skill_id": [
                        "type": "string",
                        "description": "The skill's canonical id (e.g. 'podcast_generation'). See the '## Skills' section of the system prompt for available ids.",
                    ],
                ],
                required: ["skill_id"]
            ),
        ]
    }

    /// Builds an OpenAI-compatible function-tool dictionary.
    private static func tool(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }
}
