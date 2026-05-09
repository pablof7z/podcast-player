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

        let reference = LLMModelReference(storedID: store.state.settings.llmModel)
        guard LLMProviderCredentialResolver.hasAPIKey(for: reference.provider) else {
            logger.warning("No \(reference.provider.displayName, privacy: .public) key available for Nostr agent reply")
            return nil
        }

        let senderName = displayName(for: senderPubkey)
        var messages: [[String: Any]] = [
            ["role": "system", "content": AgentPrompt.build(for: store.state)],
            ["role": "user", "content": "[from \(senderName) via Nostr]\n\(trimmed)"],
        ]
        let batchID = UUID()

        for _ in 0..<maxTurns {
            let result: AgentResult
            do {
                result = try await AgentLLMClient.streamCompletion(
                    messages: messages,
                    tools: AgentTools.schema + AgentTools.podcastSchema,
                    model: store.state.settings.llmModel,
                    feature: CostFeature.agentNostr,
                    onPartialContent: { _ in }
                )
            } catch {
                logger.error("Nostr agent turn failed: \(error, privacy: .public)")
                return nil
            }

            messages.append(result.assistantMessage)

            if result.toolCalls.isEmpty {
                let text = (result.assistantMessage["content"] as? String)?.trimmed ?? ""
                return text.isEmpty ? nil : text
            }

            for toolCall in result.toolCalls {
                let resultJSON = await AgentTools.dispatch(
                    name: toolCall.name,
                    argsJSON: toolCall.arguments,
                    store: store,
                    batchID: batchID,
                    podcastDeps: podcastDeps
                )
                messages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": resultJSON,
                ])
            }
        }

        logger.warning("Nostr agent turn reached max turn limit")
        return nil
    }

    private func displayName(for pubkey: String) -> String {
        store.friend(identifier: pubkey)?.displayName ?? "Nostr contact \(String(pubkey.prefix(8)))"
    }
}
