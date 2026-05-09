import SwiftUI

extension AppTheme {

    // MARK: - Brand colors

    enum Brand {
        static let elevenLabsTint = SwiftUI.Color(red: 0, green: 0.78, blue: 0.62)
    }

    // MARK: - Semantic tints

    enum Tint {
        static let error = SwiftUI.Color.red
        static let errorOnDark = SwiftUI.Color(red: 1.0, green: 0.7, blue: 0.7)
        static let onboardingChipAI = SwiftUI.Color(red: 0.80, green: 0.70, blue: 1.0)
        static let onboardingChipFriends = SwiftUI.Color(red: 0.60, green: 0.88, blue: 1.0)
        static let onboardingChipFeedback = SwiftUI.Color(red: 0.70, green: 1.0, blue: 0.85)
        static let agentSurface = SwiftUI.Color.indigo
        static let hairline = SwiftUI.Color.secondary.opacity(0.18)
        static let surfaceMuted = SwiftUI.Color.secondary.opacity(0.08)
        static let surfaceFaint = SwiftUI.Color.secondary.opacity(0.04)
        static let dimmed = SwiftUI.Color.secondary.opacity(0.4)
        static let placeholder = SwiftUI.Color.secondary.opacity(0.15)
    }

    // MARK: - Gradients

    enum Gradients {
        static let agentAccent = LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.20, blue: 0.84),
                Color(red: 0.14, green: 0.45, blue: 0.92),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let onboardingNebula = LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.04, blue: 0.20),
                Color(red: 0.18, green: 0.10, blue: 0.42),
                Color(red: 0.10, green: 0.32, blue: 0.66),
                Color(red: 0.04, green: 0.55, blue: 0.74)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let onboardingSparkle = LinearGradient(
            colors: [.white, Color(red: 0.85, green: 0.92, blue: 1.0)],
            startPoint: .top,
            endPoint: .bottom
        )

        static let onboardingSuccess = LinearGradient(
            colors: [.white, Color(red: 0.7, green: 1.0, blue: 0.85)],
            startPoint: .top,
            endPoint: .bottom
        )

        static let agentChatBackground = LinearGradient(
            colors: [
                Color(.systemBackground),
                AppTheme.Tint.agentSurface.opacity(0.05),
                Color.blue.opacity(0.04),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
