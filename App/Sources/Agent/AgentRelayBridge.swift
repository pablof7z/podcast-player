import Foundation
import os.log

@MainActor
final class AgentRelayBridge {
    private let logger = Logger.app("AgentRelayBridge")
    private let store: AppStateStore
    /// Live podcast-tool dependencies. Nil only for callers that don't have a
    /// `PlaybackState` handy (Nostr-only headless flows); podcast tool calls
    /// then return a typed error envelope rather than crashing.
    private let podcastDeps: PodcastAgentToolDeps?
    private let maxTurns = 8

    init(store: AppStateStore, playback: PlaybackState? = nil) {
        self.store = store
        self.podcastDeps = playback.map { LivePodcastAgentToolDeps.make(store: store, playback: $0) }
    }

    func reply(to content: String, from senderPubkey: String) async -> String? {
        let trimmed = content.trimmed
        guard !trimmed.isEmpty else { return nil }

        let reference = LLMModelReference(storedID: store.state.settings.agentInitialModel)
        guard LLMProviderCredentialResolver.hasAPIKey(for: reference.provider) else {
            logger.warning("No \(reference.provider.displayName, privacy: .public) key available for Nostr agent reply")
            return nil
        }
        // Local upgrade flag mirrors AgentChatSession.isUpgraded — flipped when
        // the agent calls `upgrade_thinking`. Scoped to a single inbound reply
        // (each Nostr message gets a fresh bridge run).
        var isUpgraded = false

        let senderName = displayName(for: senderPubkey)
        let systemPrompt = AgentPrompt.build(for: store.state)
        let userText = "[from \(senderName) via Nostr]\n\(trimmed)"
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userText],
        ]
        let batchID = UUID()
        let collector = AgentRunCollector(
            id: batchID,
            source: .nostrInbound,
            initialInput: userText,
            systemPrompt: systemPrompt
        )
        var turnNumber = 0

        for _ in 0..<maxTurns {
            let messagesBeforeCall = messages
            let result: AgentResult
            let modelForTurn = isUpgraded
                ? store.state.settings.agentThinkingModel
                : store.state.settings.agentInitialModel
            do {
                result = try await AgentLLMClient.streamCompletion(
                    messages: messages,
                    tools: AgentTools.schema + AgentTools.podcastSchema,
                    model: modelForTurn,
                    feature: CostFeature.agentNostr,
                    onPartialContent: { _ in }
                )
            } catch {
                logger.error("Nostr agent turn failed: \(error, privacy: .public)")
                collector.appendTurn(
                    turnNumber: turnNumber,
                    messagesBeforeCall: messagesBeforeCall,
                    apiResponse: nil,
                    toolDispatches: []
                )
                collector.finish(outcome: .failed, failureReason: error.localizedDescription)
                return nil
            }

            messages.append(result.assistantMessage)
            let apiResponse = makeAPIResponse(from: result)

            if result.toolCalls.isEmpty {
                collector.appendTurn(
                    turnNumber: turnNumber,
                    messagesBeforeCall: messagesBeforeCall,
                    apiResponse: apiResponse,
                    toolDispatches: []
                )
                collector.finish(outcome: .completed)
                let text = (result.assistantMessage["content"] as? String)?.trimmed ?? ""
                return text.isEmpty ? nil : text
            }

            var toolDispatches: [AgentToolDispatch] = []
            for toolCall in result.toolCalls {
                let resultJSON: String
                if toolCall.name == AgentTools.Names.upgradeThinking {
                    isUpgraded = true
                    resultJSON = AgentTools.toolSuccess([
                        "upgraded": true,
                        "model": store.state.settings.agentThinkingModel,
                    ])
                } else {
                    resultJSON = await AgentTools.dispatch(
                        name: toolCall.name,
                        argsJSON: toolCall.arguments,
                        store: store,
                        batchID: batchID,
                        podcastDeps: podcastDeps
                    )
                }
                messages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": resultJSON,
                ])
                toolDispatches.append(makeToolDispatch(call: toolCall, resultJSON: resultJSON))
            }
            collector.appendTurn(
                turnNumber: turnNumber,
                messagesBeforeCall: messagesBeforeCall,
                apiResponse: apiResponse,
                toolDispatches: toolDispatches
            )
            turnNumber += 1
        }

        collector.finish(outcome: .turnsExhausted)
        logger.warning("Nostr agent turn reached max turn limit")
        return nil
    }

    private func makeAPIResponse(from result: AgentResult) -> AgentAPIResponse {
        let runToolCalls: [AgentRunToolCall] = result.toolCalls.map { call in
            let parsedArgs = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any]) ?? [:]
            return AgentRunToolCall(id: call.id, name: call.name, arguments: parsedArgs)
        }
        let usage = result.tokensUsed ?? AgentTokenUsage(promptTokens: 0, completionTokens: 0, cachedTokens: nil)
        return AgentAPIResponse(
            assistantMessage: result.assistantMessage,
            toolCalls: runToolCalls,
            tokensUsed: usage
        )
    }

    private func makeToolDispatch(call: AgentToolCall, resultJSON: String) -> AgentToolDispatch {
        let argsDict = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any]) ?? [:]
        let resultDict: [String: Any]
        if let parsed = try? JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: Any] {
            resultDict = parsed
        } else {
            resultDict = ["raw": resultJSON]
        }
        let errorMessage = resultDict["error"] as? String
        return AgentToolDispatch(
            toolCallID: call.id,
            toolName: call.name,
            arguments: argsDict,
            result: resultDict,
            error: errorMessage
        )
    }

    private func displayName(for pubkey: String) -> String {
        store.friend(identifier: pubkey)?.displayName ?? "Nostr contact \(String(pubkey.prefix(8)))"
    }
}
