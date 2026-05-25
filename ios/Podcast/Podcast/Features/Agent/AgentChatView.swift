import SwiftUI

// MARK: - AgentChatView
//
// Full-screen chat surface for the kernel-owned agent conversation.
//
// Doctrine:
//   D7 — every state mutation is Rust-side. The view dispatches
//        `podcast.agent.send` / `podcast.agent.clear` and re-renders
//        from the next snapshot tick. There is no local message
//        store on the iOS side.
//   D2 — `model.podcastSnapshot?.agent` is the single source of
//        truth for the transcript and the `isBusy` flag.
//   Typography — SF system font everywhere (no serifs), via the
//        existing `PodcastFont` tokens.
//
// Feature #32 ships the UI scaffold: Rust appends the user message
// and a canned assistant reply. Real LLM integration replaces the
// canned reply without changing this view.

struct AgentChatView: View {
    @Environment(KernelModel.self) private var model

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private var snapshot: AgentSnapshot? { model.podcastSnapshot?.agent }
    private var messages: [AgentMessageSummary] { snapshot?.messages ?? [] }
    private var isBusy: Bool { snapshot?.isBusy ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
            }
            .podcastScreenBackground()
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.dispatch(
                            namespace: "podcast.agent",
                            body: ["op": "clear"]
                        )
                    } label: {
                        Image(systemName: "trash")
                            .font(PodcastFont.callout)
                    }
                    .disabled(messages.isEmpty)
                    .accessibilityLabel("Clear conversation")
                }
            }
        }
    }

    // MARK: Transcript scroll

    @ViewBuilder
    private var transcript: some View {
        if messages.isEmpty && !isBusy {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PodcastSpace.m) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .accessibilityIdentifier(
                                    "agent-message-\(message.role)"
                                )
                        }
                        if isBusy && messages.last?.role != "assistant" {
                            // No assistant placeholder in the transcript yet
                            // but the kernel is composing — show a standalone
                            // typing bubble so the user has feedback.
                            MessageBubbleView(
                                message: AgentMessageSummary(
                                    id: "typing-placeholder",
                                    role: "assistant",
                                    content: "",
                                    createdAt: 0,
                                    isGenerating: true
                                )
                            )
                            .id("typing-placeholder")
                        }
                    }
                    .padding(.horizontal, PodcastSpace.l)
                    .padding(.top, PodcastSpace.l)
                    .padding(.bottom, PodcastSpace.m)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isBusy) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let target: String? = if isBusy && messages.last?.role != "assistant" {
            "typing-placeholder"
        } else {
            messages.last?.id
        }
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: PodcastSpace.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(PodcastColor.accent)
            Text("Ask the agent anything")
                .font(PodcastFont.title)
            Text("Ask about your shows, recent episodes, or what to listen to next.")
                .font(PodcastFont.callout)
                .foregroundStyle(PodcastColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PodcastSpace.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PodcastColor.hairlineSoft)
                .frame(height: 0.5)
            HStack(alignment: .bottom, spacing: PodcastSpace.s) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(PodcastFont.body)
                    .lineLimit(1...5)
                    .padding(.horizontal, PodcastSpace.m)
                    .padding(.vertical, PodcastSpace.s + 2)
                    .background(
                        RoundedRectangle(
                            cornerRadius: PodcastSpace.radiusSmall,
                            style: .continuous
                        )
                        .fill(PodcastColor.surface)
                    )
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                    .accessibilityIdentifier("agent-input-field")

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(
                            canSend ? PodcastColor.accent : PodcastColor.textTertiary
                        )
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("agent-send-button")
            }
            .padding(.horizontal, PodcastSpace.l)
            .padding(.vertical, PodcastSpace.s)
        }
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    private func sendMessage() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        model.dispatch(
            namespace: "podcast.agent",
            body: ["op": "send", "message": trimmed]
        )
        draft = ""
        inputFocused = true
    }
}
