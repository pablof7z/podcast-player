import SwiftUI

// MARK: - VoiceOrbView

/// The animated agent orb. Shape and animation key off the conversation
/// state so the user has a glanceable signal of what the system is doing
/// without reading the captions.
///
/// Reused on Today (peripheral state) and Ask (entry chrome) per the
/// `ux-15-liquid-glass-system.md` brief — exposed as a small public surface
/// so other tabs can render the orb without depending on the manager.
struct VoiceOrbView: View {

    /// Visual state. Maps roughly to `AudioConversationState` but is kept
    /// independent so the orb can be driven by other sources (e.g. the
    /// briefing player on Today).
    enum Mode: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case ducked
        case error
    }

    let mode: Mode
    /// Diameter in points. Default sized for full-screen voice mode; pass
    /// a smaller value (e.g. 64) when embedding in a chrome row.
    var diameter: CGFloat = 220

    @State private var pulseAnchor: Date = .init()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let phase = context.date.timeIntervalSince(pulseAnchor)
            ZStack {
                // Outer glow halo — pulses while listening / speaking.
                Circle()
                    .fill(haloGradient)
                    .frame(width: diameter * 1.4, height: diameter * 1.4)
                    .opacity(haloOpacity(phase: phase))
                    .blur(radius: 28)
                    .scaleEffect(haloScale(phase: phase))

                // Core orb — the agent gradient.
                Circle()
                    .fill(coreGradient)
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .scaleEffect(coreScale(phase: phase))
                    .shadow(color: glowColor.opacity(0.45), radius: 20, x: 0, y: 8)

                // Inner shimmer — subtle highlight that drifts.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.55), .clear],
                            center: shimmerCenter(phase: phase),
                            startRadius: 0,
                            endRadius: diameter * 0.45
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .blendMode(.plusLighter)
                    .opacity(0.6)
            }
            .compositingGroup()
            .accessibilityHidden(true)
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .animation(.easeInOut(duration: 0.45), value: mode)
    }

    // MARK: - Style

    private var coreGradient: LinearGradient {
        switch mode {
        case .error:
            return LinearGradient(
                colors: [.red.opacity(0.7), .orange.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ducked:
            return LinearGradient(
                colors: [.gray.opacity(0.45), .gray.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return AppTheme.Gradients.agentAccent
        }
    }

    private var haloGradient: RadialGradient {
        RadialGradient(
            colors: [glowColor.opacity(0.6), .clear],
            center: .center,
            startRadius: 0,
            endRadius: diameter
        )
    }

    private var glowColor: Color {
        switch mode {
        case .listening: return Color(red: 0.45, green: 0.78, blue: 1.0)
        case .thinking: return Color(red: 0.62, green: 0.45, blue: 1.0)
        case .speaking: return Color(red: 0.36, green: 0.85, blue: 0.78)
        case .error: return .red
        case .ducked: return .gray
        case .idle: return Color(red: 0.36, green: 0.20, blue: 0.84)
        }
    }

    // MARK: - Animation helpers

    private func haloOpacity(phase: TimeInterval) -> Double {
        switch mode {
        case .listening, .speaking:
            let oscillation = (sin(phase * 2.4) + 1) / 2
            return 0.35 + 0.45 * oscillation
        case .thinking:
            return 0.55
        case .ducked: return 0.15
        case .error: return 0.6
        case .idle: return 0.3
        }
    }

    private func haloScale(phase: TimeInterval) -> CGFloat {
        switch mode {
        case .listening:
            let oscillation = CGFloat((sin(phase * 2.4) + 1) / 2)
            return 0.95 + 0.10 * oscillation
        case .speaking:
            let oscillation = CGFloat((sin(phase * 5.0) + 1) / 2)
            return 0.92 + 0.18 * oscillation
        case .thinking:
            let oscillation = CGFloat((sin(phase * 1.4) + 1) / 2)
            return 0.96 + 0.06 * oscillation
        case .idle: return 0.95
        case .ducked: return 0.85
        case .error: return 1.0
        }
    }

    private func coreScale(phase: TimeInterval) -> CGFloat {
        switch mode {
        case .listening:
            let oscillation = CGFloat((sin(phase * 2.4) + 1) / 2)
            return 0.97 + 0.04 * oscillation
        case .speaking:
            let oscillation = CGFloat((sin(phase * 5.0) + 1) / 2)
            return 0.95 + 0.08 * oscillation
        case .thinking:
            let oscillation = CGFloat((sin(phase * 1.4) + 1) / 2)
            return 0.99 + 0.02 * oscillation
        case .idle: return 1.0
        case .ducked: return 0.85
        case .error: return 1.0
        }
    }

    private func shimmerCenter(phase: TimeInterval) -> UnitPoint {
        let x = 0.5 + 0.18 * cos(phase * 0.6)
        let y = 0.45 + 0.18 * sin(phase * 0.45)
        return UnitPoint(x: x, y: y)
    }
}

// MARK: - Preview

#Preview("Idle") {
    VoiceOrbView(mode: .idle).padding()
}

#Preview("Listening") {
    VoiceOrbView(mode: .listening).padding()
}

#Preview("Speaking") {
    VoiceOrbView(mode: .speaking).padding()
}

#Preview("Error") {
    VoiceOrbView(mode: .error).padding()
}
