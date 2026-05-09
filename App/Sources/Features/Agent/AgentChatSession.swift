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

    private let store: AppStateStore
    private let history: ChatHistoryStore
    private var rawMessages: [[String: Any]] = []
    private var rawMessageCountAtLastSendStart: Int = 0
    private var messageCountAtLastSendStart: Int = 0
    /// The currently-running send task. Held so `cancelSend()` can cancel it.
    private var sendingTask: Task<Void, Never>?

    private let maxTurns: Int = 20

    init(store: AppStateStore, history: ChatHistoryStore = .shared) {
        self.store = store
        self.history = history
        let loaded = history.load()
        self.messages = loaded
        self.loadedFromHistory = !loaded.isEmpty
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
        sendingTask = Task { await send(msg) }
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
        sendingTask = Task { await regenerateSend(userText) }
    }

    /// Like `send(_:)` but skips appending the user message — it's already in
    /// both `messages` and `rawMessages` from the original turn.
    private func regenerateSend(_ text: String) async {
        let key: String
        do {
            guard let storedKey = try OpenRouterCredentialStore.apiKey() else {
                phase = .failed("OpenRouter is not connected. Add a key in Settings.")
                return
            }
            key = storedKey
        } catch {
            phase = .failed("OpenRouter credential could not be read. Reconnect in Settings.")
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

        await runAgentTurns(apiKey: key, batchID: UUID())
    }

    /// Begins an agent turn in a stored `Task` so the caller can cancel it via
    /// `cancelSend()`. Returns immediately; observe `phase` for progress.
    func startSend(_ text: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, canSend else { return }
        sendingTask = Task { await send(trimmed) }
    }

    private func send(_ text: String) async {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }

        let key: String
        do {
            guard let storedKey = try OpenRouterCredentialStore.apiKey() else {
                phase = .failed("OpenRouter is not connected. Add a key in Settings.")
                return
            }
            key = storedKey
        } catch {
            phase = .failed("OpenRouter credential could not be read. Reconnect in Settings.")
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

        await runAgentTurns(apiKey: key, batchID: UUID())
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
    ///   - apiKey: A valid OpenRouter API key.
    ///   - batchID: Stable identifier for the tool-action batch started by this turn.
    private func runAgentTurns(apiKey: String, batchID: UUID) async {
        var batchActionCount = 0

        for _ in 0..<maxTurns {
            streamingContent = ""

            let result: AgentResult
            do {
                result = try await AgentOpenRouterClient.streamCompletion(
                    messages: rawMessages,
                    tools: AgentTools.schema,
                    apiKey: apiKey,
                    model: store.state.settings.llmModel
                ) { [weak self] partial in
                    self?.streamingContent = partial
                }
            } catch is CancellationError {
                // User tapped Stop — discard partial content and return to idle.
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

            if result.toolCalls.isEmpty {
                lastFailedMessage = nil
                phase = .idle
                history.save(messages)
                return
            }

            for toolCall in result.toolCalls {
                guard !Task.isCancelled else {
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
                    batchID: batchID
                )
                rawMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": resultJSON,
                ])
                batchActionCount += store.state.agentActivity.count - activityCountBefore
            }
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

        resetStreamingState()
        let limitMsg = "The agent reached its turn limit. Try a simpler request or start a new conversation."
        messages.append(ChatMessage(role: .error, text: limitMsg))
        phase = .failed(limitMsg)
        history.save(messages)
    }

    /// Clears transient streaming state that must be reset on every exit path.
    ///
    /// Call this before setting `phase` on any return or throw so the typing
    /// indicator and tool-status label are never left in a stale state.
    private func resetStreamingState() {
        streamingContent = nil
        currentToolName = nil
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
