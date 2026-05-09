import SwiftUI

// TODO: Top-level "Ask" tab. Conversational entry point to the agent across
// all subscribed podcasts. Distinct from `Features/Agent/AgentChatView.swift`
// (the template's tasks-scoped chat) — this one is podcast-corpus-scoped and
// will eventually share underlying session infrastructure.

struct AskAgentView: View {
    var body: some View {
        Text("Ask")
            .padding()
    }
}
