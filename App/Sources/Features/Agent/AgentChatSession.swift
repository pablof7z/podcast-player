import Foundation
import Observation
import os.log

@MainActor
@Observable
final class AgentChatSession {

    private let logger = Logger.app("AgentChatSession")
    enum Phase: Equatable {
        case idle
        case sending
        case failed(String)
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var phase: Phase = .idle
    private(set) var loadedFromHistory: Bool = false
    private(set) var lastFailedMessage: String?
    /// Partial assistant content received so far during a streaming turn.
    /// Non-nil (including empty string) while a turn is actively streaming text.
    /// Nil when idle, sending tool-only turns, or after the turn completes.
    private(set) var streamingContent: String?
    /// The tool currently being dispatched, if any.
    /// Set immediately before each `AgentTools.dispatch` call and cleared
    /// once the inner tool loop finishes. Drives the status label in the
    /// typing indicator so the user can see what the agent is doing.
    private(set) var currentToolName: String?
    /// Composer prefill captured from `AppStateStore.pendingTranscriptAgentContext`
    /// at init time. The view drains this exactly once via
    /// `consumeSeededDraft()` on `.onAppear`; subsequent reads return nil so a
    /// re-presentation of the chat sheet starts blank.
    private var seededDraft: String?

    private let store: AppStateStore
    private let history: ChatHistoryStore
    /// Live podcast-tool dependencies. Nil only in test/preview contexts that
    /// chose not to wire the player; podcast tool calls return a typed error
    /// in that case rather than crashing.
    private let podcastDeps: PodcastAgentToolDeps?
    private var rawMessages: [[String: Any]] = []
    private var rawMessageCountAtLastSendStart: Int = 0
    private var messageCountAtLastSendStart: Int = 0
    /// The currently-running send task. Held so `cancelSend()` can cancel it.
    private var sendingTask: Task<Void, Never>?

    private let maxTurns: Int = 20

    init(
        store: AppStateStore,
        playback: PlaybackState? = nil,
        history: ChatHistoryStore = .shared
    ) {
        self.store = store
        self.history = history
        self.podcastDeps = playback.map { LivePodcastAgentToolDeps.make(store: store, playback: $0) }
        let loaded = history.load()
        self.messages = loaded
        self.loadedFromHistory = !loaded.isEmpty
        // Drain the long-press → ask-agent context. Read-and-clear so a later
        // sheet re-open starts blank. Auto-send is intentionally NOT done here
        // — long-press is too easy to mistrigger; let the user confirm via Send.
        //
        // Chapter context wins over transcript context: the chapter long-press
        // is the primary user-visible affordance now; transcript-segment
        // contexts only get written by internal-only surfaces (clip composer,
        // quote share). If both happen to be pending, the chapter one is the
        // one the user just tapped.
        if let chapter = store.pendingChapterAgentContext {
            self.seededDraft = chapter.prefilledDraft
            store.pendingChapterAgentContext = nil
            store.pendingTranscriptAgentContext = nil
        } else if let pending = store.pendingTranscriptAgentContext {
            self.seededDraft = pending.prefilledDraft
            store.pendingTranscriptAgentContext = nil
        }
    }

    /// Returns the prefilled draft once and clears it. View calls this from
    /// `.onAppear` after wiring the session.
    func consumeSeededDraft() -> String? {
        let value = seededDraft
        seededDraft = nil
        return value
    }

    var canSend: Bool {
        if case .sending = phase { return false }
        return true
    }

    /// Cancels an in-flight streaming turn, discarding any partial content.
    /// Transitions `phase` back to `.idle` so the user can send a new message.
    func cancelSend() {
        sendingTask?.cancel()
        sendingTask = nil
    }

    func clearHistory() {
        history.clear()
        messages = []
        rawMessages = []
        loadedFromHistory = false
        phase = .idle
        lastFailedMessage = nil
        streamingContent = nil
        currentToolName = nil
    }

    func retry() {
        guard let msg = lastFailedMessage, canSend else { return }
        rawMessages = Array(rawMessages.prefix(rawMessageCountAtLastSendStart))
        messages = Array(messages.prefix(messageCountAtLastSendStart))
        lastFailedMessage = nil
        sendingTask = Task { await send(msg, source: .typedChat) }
    }

    /// Regenerates the last assistant response by dropping it from the
    /// transcript and re-running the preceding user turn.
    ///
    /// Only valid when the last two visible messages are `.user` then `.assistant`
    /// (i.e. a pure text turn with no tool calls). Tool-batch turns have their
    /// own undo flow via the activity chip and are excluded here.
    ///
    /// Idempotent guard: does nothing if `phase == .sending`.
    var canRegenerate: Bool {
        guard canSend else { return false }
        // The last two messages must be user → assistant (no tool batch in between).
        let visible = messages.filter {
            if case .toolBatch = $0.role { return false }
            if case .error = $0.role { return false }
            return true
        }
        guard visible.count >= 2 else { return false }
        let last = visible[visible.count - 1]
        let prev = visible[visible.count - 2]
        guard case .assistant = last.role, case .user = prev.role else { return false }
        return true
    }

    func regenerateLast() {
        guard canRegenerate else { return }

        // Find and remove the last assistant message from the UI transcript.
        guard let lastAssistantIdx = messages.lastIndex(where: {
            if case .assistant = $0.role { return true }
            return false
        }) else { return }
        let userText: String
        // Walk backwards from just before the assistant message to find the preceding user message.
        guard let prevUserIdx = messages[..<lastAssistantIdx].lastIndex(where: {
            if case .user = $0.role { return true }
            return false
        }) else { return }
        userText = messages[prevUserIdx].text

        // Drop the assistant message from the display transcript.
        messages.remove(at: lastAssistantIdx)

        // Drop the corresponding rawMessage entry — the last assistant role.
        if let rawIdx = rawMessages.lastIndex(where: { ($0["role"] as? String) == "assistant" }) {
            rawMessages.remove(at: rawIdx)
        }

        // Reset bookkeeping so that a subsequent error can be retried cleanly
        // from the same position (mirrors the accounting in `send(_:)`).
        rawMessageCountAtLastSendStart = rawMessages.count - 1  // user message is already in rawMessages
        messageCountAtLastSendStart = messages.count - 1        // user message is already in messages
        lastFailedMessage = nil

        history.save(messages)
        sendingTask = Task { await regenerateSend(userText, source: .typedChat) }
    }

    /// Like `send(_:)` but skips appending the user message — it's already in
    /// both `messages` and `rawMessages` from the original turn.
    private func regenerateSend(_ text: String, source: AgentRunSource) async {
        guard selectedProviderHasCredential() else {
            phase = .failed(missingCredentialMessage())
            return
        }

        // Refresh system prompt for this turn.
        if !rawMessages.isEmpty {
            rawMessages[0] = ["role": "system", "content": AgentPrompt.build(for: store.state)]
        }

        rawMessageCountAtLastSendStart = rawMessages.count
        messageCountAtLastSendStart = messages.count
        lastFailedMessage = text
        phase = .sending
        history.save(messages)

        await runAgentTurns(batchID: UUID(), source: source, initialInput: text)
    }

    /// Begins an agent turn in a stored `Task` so the caller can cancel it via
    /// `cancelSend()`. Returns immediately; observe `phase` for progress.
    func startSend(_ text: String, source: AgentRunSource = .typedChat) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, canSend else { return }
        sendingTask = Task { await send(trimmed, source: source) }
    }

    private func send(_ text: String, source: AgentRunSource) async {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }

        guard selectedProviderHasCredential() else {
            phase = .failed(missingCredentialMessage())
            return
        }

        if rawMessages.isEmpty {
            rawMessages.append([
                "role": "system",
                "content": AgentPrompt.build(for: store.state),
            ])
            seedRawMessagesFromHistory()
        } else {
            // Refresh the system prompt every turn so that items created or
            // edited during this session — including those the agent just
            // modified — are reflected in context for subsequent turns.
            rawMessages[0] = [
                "role": "system",
                "content": AgentPrompt.build(for: store.state),
            ]
        }

        rawMessageCountAtLastSendStart = rawMessages.count
        messageCountAtLastSendStart = messages.count
        lastFailedMessage = trimmed

        rawMessages.append(["role": "user", "content": trimmed])
        messages.append(ChatMessage(role: .user, text: trimmed))
        phase = .sending
        history.save(messages)

        await runAgentTurns(batchID: UUID(), source: source, initialInput: trimmed)
    }

    /// Executes the streaming agent turn-loop, processing LLM responses and tool
    /// calls until the model produces a text-only reply, the task is cancelled, a
    /// network error occurs, or `maxTurns` is exhausted.
    ///
    /// Call sites (`send` and `regenerateSend`) are responsible for seeding
    /// `rawMessages`, setting `phase = .sending`, and capturing bookkeeping
    /// snapshots before invoking this method.  On every exit path this method
    /// leaves `phase` in `.idle` or `.failed` and persists `messages` via `history`.
    ///
    /// - Parameters:
    ///   - batchID: Stable identifier for the tool-action batch *and* the
    ///     `AgentRun` produced by this turn loop.
    ///   - source: How this run was triggered (typed chat, voice, Nostr, etc.).
    ///   - initialInput: User-visible prompt that started the run, recorded on
    ///     the `AgentRun` for the Run History UI.
    private func runAgentTurns(batchID: UUID, source: AgentRunSource, initialInput: String) async {
        var batchActionCount = 0
        let systemPromptSnapshot = (rawMessages.first?["content"] as? String) ?? ""
        let collector = AgentRunCollector(
            id: batchID,
            source: source,
            initialInput: initialInput,
            systemPrompt: systemPromptSnapshot
        )
        var turnNumber = 0

        for _ in 0..<maxTurns {
            streamingContent = ""

            let messagesBeforeCall = rawMessages
            let result: AgentResult
            do {
                result = try await AgentLLMClient.streamCompletion(
                    messages: rawMessages,
                    tools: AgentTools.schema + AgentTools.podcastSchema,
                    model: store.state.settings.llmModel
                ) { [weak self] partial in
                    self?.streamingContent = partial
                }
            } catch is CancellationError {
                // User tapped Stop — discard partial content and return to idle.
                collector.appendTurn(
                    turnNumber: turnNumber,
                    messagesBeforeCall: messagesBeforeCall,
                    apiResponse: nil,
                    toolDispatches: []
                )
                collector.finish(outcome: .cancelled)
                resetStreamingState()
                lastFailedMessage = nil
                phase = .idle
                history.save(messages)
                return
            } catch {
                // Preserve any text the agent had already streamed before the
                // error so the user can see what it was saying and retry with
                // that context visible. Only save if there is meaningful content.
                preservePartialContentIfNeeded()
                collector.appendTurn(
                    turnNumber: turnNumber,
                    messagesBeforeCall: messagesBeforeCall,
                    apiResponse: nil,
                    toolDispatches: []
                )
                collector.finish(outcome: .failed, failureReason: error.localizedDescription)
                resetStreamingState()
                let msg = "Couldn't reach the agent. \(error.localizedDescription)"
                messages.append(ChatMessage(role: .error, text: msg))
                phase = .failed(msg)
                history.save(messages)
                return
            }

            resetStreamingState()
            rawMessages.append(result.assistantMessage)

            if let content = result.assistantMessage["content"] as? String,
               !content.isBlank {
                messages.append(ChatMessage(role: .assistant, text: content))
            }

            let apiResponse = makeAPIResponse(from: result)

            if result.toolCalls.isEmpty {
                collector.appendTurn(
                    turnNumber: turnNumber,
                    messagesBeforeCall: messagesBeforeCall,
                    apiResponse: apiResponse,
                    toolDispatches: []
                )
                collector.finish(outcome: .completed)
                lastFailedMessage = nil
                phase = .idle
                history.save(messages)
                return
            }

            var toolDispatches: [AgentToolDispatch] = []
            for toolCall in result.toolCalls {
                guard !Task.isCancelled else {
                    collector.appendTurn(
                        turnNumber: turnNumber,
                        messagesBeforeCall: messagesBeforeCall,
                        apiResponse: apiResponse,
                        toolDispatches: toolDispatches
                    )
                    collector.finish(outcome: .cancelled)
                    resetStreamingState()
                    lastFailedMessage = nil
                    phase = .idle
                    history.save(messages)
                    return
                }
                currentToolName = toolCall.name
                // Snapshot the activity log before dispatch so we can detect
                // whether the tool recorded any activity entries. Read-only
                // tools (e.g. find_items) don't record activity, so this delta
                // is 0 for them — preventing a stale "Agent ran 0 actions" chip.
                let activityCountBefore = store.state.agentActivity.count
                let resultJSON = await AgentTools.dispatch(
                    name: toolCall.name,
                    argsJSON: toolCall.arguments,
                    store: store,
                    batchID: batchID,
                    podcastDeps: podcastDeps
                )
                rawMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": resultJSON,
                ])
                batchActionCount += store.state.agentActivity.count - activityCountBefore
                toolDispatches.append(makeToolDispatch(call: toolCall, resultJSON: resultJSON))
            }
            collector.appendTurn(
                turnNumber: turnNumber,
                messagesBeforeCall: messagesBeforeCall,
                apiResponse: apiResponse,
                toolDispatches: toolDispatches
            )
            turnNumber += 1
            resetStreamingState()

            // Only render a tool-batch chip when at least one mutating action
            // was recorded. Read-only tool calls (e.g. find_items) don't write
            // to the activity log, so batchActionCount stays 0 for them and
            // we skip the chip entirely — no "Agent ran 0 actions" noise.
            if batchActionCount > 0 {
                if let lastBatchIdx = messages.lastIndex(where: { msg in
                    if case .toolBatch(let id, _) = msg.role, id == batchID { return true }
                    return false
                }) {
                    messages[lastBatchIdx] = ChatMessage(
                        role: .toolBatch(batchID: batchID, count: batchActionCount),
                        text: ""
                    )
                } else {
                    messages.append(ChatMessage(
                        role: .toolBatch(batchID: batchID, count: batchActionCount),
                        text: ""
                    ))
                }
            }
            history.save(messages)
        }

        collector.finish(outcome: .turnsExhausted)
        resetStreamingState()
        let limitMsg = "The agent reached its turn limit. Try a simpler request or start a new conversation."
        messages.append(ChatMessage(role: .error, text: limitMsg))
        phase = .failed(limitMsg)
        history.save(messages)
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

    /// Clears transient streaming state that must be reset on every exit path.
    ///
    /// Call this before setting `phase` on any return or throw so the typing
    /// indicator and tool-status label are never left in a stale state.
    private func resetStreamingState() {
        streamingContent = nil
        currentToolName = nil
    }

    private func selectedProviderHasCredential() -> Bool {
        let reference = LLMModelReference(storedID: store.state.settings.llmModel)
        return LLMProviderCredentialResolver.hasAPIKey(for: reference.provider)
    }

    private func missingCredentialMessage() -> String {
        let reference = LLMModelReference(storedID: store.state.settings.llmModel)
        return LLMProviderCredentialResolver.missingCredentialMessage(for: reference.provider)
    }

    /// Saves any non-empty partial streaming content as an assistant message
    /// before an error terminates the turn.
    ///
    /// Call this before `resetStreamingState()` on error paths only (not on
    /// cancellation, where discarding is intentional). The saved message lets
    /// the user see what the agent had already written and retry with that
    /// context visible in the transcript.
    private func preservePartialContentIfNeeded() {
        guard let partial = streamingContent,
              !partial.isBlank else { return }
        messages.append(ChatMessage(role: .assistant, text: partial))
    }

    private func seedRawMessagesFromHistory() {
        for msg in messages {
            switch msg.role {
            case .user:
                rawMessages.append(["role": "user", "content": msg.text])
            case .assistant:
                rawMessages.append(["role": "assistant", "content": msg.text])
            case .toolBatch, .error:
                continue
            }
        }
    }
}
