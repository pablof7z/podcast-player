import SwiftUI

// MARK: - MessageBubbleView
//
// Single chat bubble. User messages right-align with the accent fill;
// assistant messages left-align with the secondary surface fill.
// When `message.isGenerating` is `true` the bubble renders a typing
// indicator (three pulsing dots) instead of the message text.
//
// Extracted out of `AgentChatView.swift` so the parent stays under
// the soft 300-line limit while the chat surface grows.

struct MessageBubbleView: View {
    let message: AgentMessageSummary

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(spacing: 0) {
            if isUser {
                Spacer(minLength: PodcastSpace.xl)
            }
            bubble
            if !isUser {
                Spacer(minLength: PodcastSpace.xl)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: PodcastSpace.xs) {
            content
                .padding(.horizontal, PodcastSpace.m)
                .padding(.vertical, PodcastSpace.s + 2)
                .background(
                    RoundedRectangle(
                        cornerRadius: AppTheme.Corner.bubble,
                        style: .continuous
                    )
                    .fill(bubbleFill)
                )
                .foregroundStyle(bubbleForeground)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.isGenerating {
            TypingIndicator()
                .accessibilityLabel("Agent is typing")
        } else {
            Text(message.content)
                .font(PodcastFont.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bubbleFill: Color {
        isUser ? PodcastColor.accent : PodcastColor.surface
    }

    private var bubbleForeground: Color {
        isUser ? .white : PodcastColor.textPrimary
    }
}

// MARK: - TypingIndicator
//
// Three dots pulsing in sequence. Used by both an empty assistant bubble
// (when the kernel is composing but hasn't filled in a placeholder yet)
// and an in-place placeholder bubble (`message.isGenerating == true`).

private struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(PodcastColor.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(opacity(for: index))
            }
        }
        .frame(width: 30, height: 14)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                phase = 1
            }
        }
    }

    private func opacity(for index: Int) -> CGFloat {
        // Staggered pulse — each dot leads the next by ~0.15 of the cycle.
        let stagger = CGFloat(index) * 0.25
        let local = (phase + stagger).truncatingRemainder(dividingBy: 1)
        return 0.3 + 0.6 * sin(local * .pi)
    }
}
