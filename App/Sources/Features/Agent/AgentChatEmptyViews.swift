import SwiftUI

// MARK: - Layout

private enum Layout {
    static let bannerCloseIconSize: CGFloat = 11
    static let bannerCloseFrameSize: CGFloat = 22
    static let bannerIconSize: CGFloat = 14
    static let inputFieldPaddingH: CGFloat = 14
    static let inputFieldPaddingV: CGFloat = 10
    static let inputFieldCornerRadius: CGFloat = 22
    static let chipCornerRadius: CGFloat = 14
    static let bannerCornerRadius: CGFloat = 12
    static let welcomeIconSize: CGFloat = 44
    static let disconnectedIconSize: CGFloat = 40
}

// MARK: - Resume session banner

/// Banner shown at the top of the chat when the user is continuing a previous session.
struct AgentChatResumeBanner: View {
    @Binding var isDismissed: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: Layout.bannerIconSize, weight: .semibold))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text("Continuing from your previous session")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                withAnimation(AppTheme.Animation.spring) { isDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Layout.bannerCloseIconSize, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: Layout.bannerCloseFrameSize,
                        height: Layout.bannerCloseFrameSize
                    )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Dismiss banner")
        }
        .padding(.horizontal, Layout.inputFieldPaddingH)
        .padding(.vertical, Layout.inputFieldPaddingV)
        .glassEffect(
            .regular.tint(.indigo.opacity(0.10)),
            in: .rect(cornerRadius: Layout.bannerCornerRadius)
        )
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
    }
}

// MARK: - Welcome state

/// Empty-state view when the agent is connected but no messages have been sent yet.
struct AgentChatWelcomeView: View {
    @Binding var draft: String
    var inputFocused: FocusState<Bool>.Binding

    @Environment(AppStateStore.self) private var store
    @State private var visibleSuggestions: [String] = []

    /// Generic starter prompts shown when no context-specific suggestion applies.
    private static let genericSuggestions: [String] = [
        "What can you help me with?",
        "Set a reminder for tomorrow morning",
        "Remember I prefer dark mode and minimal UIs",
        "Save a note: ideas for my next project",
        "What did I ask you to remember?",
        "Remind me to review this in one week",
        "Remember that my timezone is Pacific",
        "Take a note: things to research today",
        "What's on my list right now?",
        "Mark my most urgent task as priority",
        "Add a task and mark it as priority",
        "Rename my task to be more descriptive",
    ]

    /// Context-aware suggestions derived from the current app state.
    /// Prepended before generic suggestions so the most relevant prompts appear first.
    private var contextualSuggestions: [String] {
        var result: [String] = []
        if store.overdueItemCount > 0 {
            result.append("What tasks are overdue?")
        }
        if store.priorityItemCount > 0 && store.overdueItemCount == 0 {
            result.append("Summarize my priority tasks")
        }
        if store.completionStreak >= 2 {
            result.append("How am I doing this week?")
        }
        if !store.friendsWithPendingItems.isEmpty {
            result.append("What do I have pending for friends?")
        }
        return result
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: Layout.welcomeIconSize, weight: .semibold))
                .foregroundStyle(AppTheme.Gradients.agentAccent)
                .symbolEffect(.pulse, options: .repeating)
            Text(timeOfDayGreeting)
                .font(AppTheme.Typography.title)
            Text("The agent can remember things, set reminders, take notes, and use tools you define.")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppTheme.Spacing.lg)
            if let summary = taskContextSummary {
                taskContextPill(summary)
                    .padding(.top, AppTheme.Spacing.xs)
            }
            if store.completionStreak >= 2 {
                streakPill(store.completionStreak)
                    .padding(.top, AppTheme.Spacing.xs)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(visibleSuggestions, id: \.self) { text in
                    suggestionChip(text)
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .onAppear { pickSuggestions() }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            Haptics.selection()
            draft = text
            inputFocused.wrappedValue = true
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                Text(text)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.inputFieldPaddingH)
            .padding(.vertical, Layout.inputFieldPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(.indigo.opacity(0.08)).interactive(),
                in: .rect(cornerRadius: Layout.chipCornerRadius)
            )
        }
        .buttonStyle(.plain)
    }

    private func pickSuggestions() {
        // Context suggestions are always shown first (up to 2), then generic ones fill the rest.
        let context = Array(contextualSuggestions.prefix(2))
        let needed = 3 - context.count
        let generic = Array(Self.genericSuggestions.shuffled().prefix(needed))
        visibleSuggestions = context + generic
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Ask your agent anything"
        }
    }

    private var taskContextSummary: String? {
        let pending = store.state.items.filter { !$0.deleted && $0.status == .pending }.count
        let overdue = store.overdueItemCount
        let doneToday = store.state.items.filter {
            !$0.deleted && $0.status == .done && Calendar.current.isDateInToday($0.updatedAt)
        }.count
        guard pending > 0 || doneToday > 0 else { return nil }
        if pending == 0 {
            return doneToday == 1 ? "1 task done today" : "\(doneToday) tasks done today"
        }
        var parts = ["\(pending) pending"]
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if doneToday > 0 { parts.append("\(doneToday) done today") }
        return parts.joined(separator: " · ")
    }

    private func taskContextPill(_ text: String) -> some View {
        let pending = store.state.items.filter { !$0.deleted && $0.status == .pending }.count
        let hasOverdue = store.overdueItemCount > 0
        let allDone = pending == 0
        let icon: String
        let color: Color
        if hasOverdue {
            icon = "clock.badge.exclamationmark"
            color = .red
        } else if allDone {
            icon = "checkmark.circle.fill"
            color = .green
        } else {
            icon = "checklist"
            color = Color.accentColor
        }
        return Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, Layout.inputFieldPaddingH)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
            .accessibilityLabel(text)
    }

    private func streakPill(_ days: Int) -> some View {
        let label = "\(days) day streak"
        return Label(label, systemImage: "flame.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, Layout.inputFieldPaddingH)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .accessibilityLabel(label)
    }
}

// MARK: - Disconnected state

/// Empty-state view shown when OpenRouter is not yet connected.
struct AgentChatDisconnectedView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()
            Image(systemName: "key.slash.fill")
                .font(.system(size: Layout.disconnectedIconSize))
                .foregroundStyle(.orange)
            Text("Connect OpenRouter to chat")
                .font(AppTheme.Typography.title)
                .multilineTextAlignment(.center)
            Text("The agent runs on a model of your choice via OpenRouter. Add your key in Settings to begin.")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppTheme.Spacing.lg)
            NavigationLink {
                OpenRouterSettingsView()
            } label: {
                Label("Open AI Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}
