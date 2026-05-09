import SwiftUI

/// Bottom sheet for picking playback rate.
///
/// One-thumb operable, every option a full-width row with a leading checkmark
/// for the current selection. Lane 1 will hand the same rate values directly
/// to `AVPlayer.rate`; nothing else here changes.
struct PlayerSpeedSheet: View {

    @Bindable var state: MockPlaybackState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Playback Speed")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.sm)

                ForEach(MockPlaybackRate.allCases) { rate in
                    rateRow(for: rate)
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

    private func rateRow(for rate: MockPlaybackRate) -> some View {
        Button {
            state.setRate(rate)
            dismiss()
        } label: {
            HStack {
                Text(rate.label)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if state.rate == rate {
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
}
