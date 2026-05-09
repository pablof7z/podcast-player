import SwiftUI

/// Auto-scrolling transcript — the player's protagonist surface.
///
/// Renders speaker chips, lights the active line, drives ScrollView to keep
/// the active line centred, and exposes tap-to-jump + long-press-to-clip
/// (placeholder; Lane 5 owns the real clip flow).
struct PlayerTranscriptScrollView: View {

    @Bindable var state: MockPlaybackState
    /// Toggles between hero glass card and the bare reading surface used in
    /// transcript-focus layout. Parent supplies whichever framing is live.
    let useGlassCard: Bool

    @State private var userScrolledManually: Bool = false
    @State private var lastAutoScrolledLineID: Int?
    @State private var clipTargetLineID: Int?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        ForEach(state.transcript) { line in
                            transcriptRow(for: line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollClipDisabled()
                .onChange(of: state.activeLineIndex) { _, newIndex in
                    guard !userScrolledManually,
                          let newIndex,
                          let id = state.transcript[safe: newIndex]?.id,
                          id != lastAutoScrolledLineID
                    else { return }
                    lastAutoScrolledLineID = id
                    withAnimation(AppTheme.Animation.easeOut) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            if userScrolledManually {
                returnToLivePill
            }
        }
        .background(transcriptBackground)
    }

    // MARK: - Row

    @ViewBuilder
    private func transcriptRow(for line: MockTranscriptLine) -> some View {
        let isActive = state.activeLine?.id == line.id

        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            speakerChip(line: line, isActive: isActive)
            Text(line.text)
                .font(isActive ? .system(size: 22, weight: .semibold) : .system(size: 18))
                .foregroundStyle(isActive ? .white : .white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? line.speakerColor.opacity(0.22) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isActive ? line.speakerColor.opacity(0.55) : .clear, lineWidth: 1)
                )
        )
        .scaleEffect(isActive ? 1.0 : 0.98)
        .animation(AppTheme.Animation.spring, value: state.activeLine?.id)
        .contentShape(Rectangle())
        .onTapGesture {
            state.jumpToLine(line)
            userScrolledManually = false
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            // Lane 5 owns the real clip-share sheet. We surface a minimal
            // placeholder so the gesture is wired and the haptics ramp lands.
            clipTargetLineID = line.id
            Haptics.medium()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.speakerName), \(line.text)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func speakerChip(line: MockTranscriptLine, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(line.speakerColor)
                .frame(width: 6, height: 6)
            Text(line.speakerName)
                .font(.system(size: 11, design: .monospaced).weight(.medium))
                .tracking(0.6)
                .foregroundStyle(isActive ? .white : .white.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(line.speakerColor.opacity(isActive ? 0.32 : 0.12))
        )
        .frame(minWidth: 60, alignment: .leading)
    }

    private var returnToLivePill: some View {
        Button {
            userScrolledManually = false
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("Return to live")
                    .font(AppTheme.Typography.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.pressable)
        .padding(.top, AppTheme.Spacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var transcriptBackground: some View {
        if useGlassCard {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            Color.clear
        }
    }
}

// MARK: - Helpers

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
