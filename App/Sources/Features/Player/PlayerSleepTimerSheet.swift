import SwiftUI

/// Bottom sheet for setting a sleep timer.
struct PlayerSleepTimerSheet: View {

    @Bindable var state: MockPlaybackState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sleep Timer")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.sm)

                ForEach(MockSleepTimer.presets) { preset in
                    timerRow(for: preset)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func timerRow(for preset: MockSleepTimer) -> some View {
        Button {
            state.setSleepTimer(preset)
            dismiss()
        } label: {
            HStack {
                Image(systemName: glyph(for: preset))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(preset.label)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if state.sleepTimer == preset {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98, opacity: 0.85))
    }

    private func glyph(for preset: MockSleepTimer) -> String {
        switch preset {
        case .off: return "moon.zzz"
        case .minutes: return "timer"
        case .endOfEpisode: return "stop.circle"
        }
    }
}
