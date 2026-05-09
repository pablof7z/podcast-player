import SwiftUI

/// Editorial podcast landing screen. Stub for now — will become the curated
/// catch-up feed (in-progress episodes, week's TLDR briefing, ambient agent
/// prompt) once the podcast modules are fleshed out.
struct HomeView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(AppTheme.Gradients.agentAccent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Today")
                    .font(AppTheme.Typography.title)
                Text("Your editorial podcast feed will live here.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
    }
}
