import SwiftUI

/// Top-level "Ask" tab — hosts the AI agent chat as a full-screen surface.
/// Wraps `AgentChatView` (formerly presented as a sheet) so it lives inline
/// in the tab bar.
struct AskAgentView: View {
    var body: some View {
        AgentChatView()
    }
}
