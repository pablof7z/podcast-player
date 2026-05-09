import SwiftUI

// MARK: - BulkDurationPickerSheet

/// Sheet that lets the user pick a preset estimated duration (or type a custom
/// number of minutes) to apply to all currently-selected items in bulk.
///
/// Preset chips cover the most common time estimates; a text field lets the user
/// enter an arbitrary minute count. A "Clear" option removes any existing estimate.
struct BulkDurationPickerSheet: View {

    /// Called with the chosen minute count, or `nil` to clear the estimate.
    var onSelect: (Int?) -> Void

    @State private var customText = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let presets: [(label: String, minutes: Int)] = [
        ("5 min",  5),
        ("10 min", 10),
        ("15 min", 15),
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
    ]

    private var customMinutes: Int? {
        guard let raw = Int(customText.trimmingCharacters(in: .whitespaces)), raw > 0 else { return nil }
        return raw
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // --- Custom minutes input ---
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Custom minutes…", text: $customText)
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            guard let mins = customMinutes else { return }
                            onSelect(mins)
                        }
                    if !customText.isEmpty {
                        Button {
                            customText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear custom duration")
                    }
                }
                .padding(AppTheme.Spacing.sm)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)

                if let mins = customMinutes {
                    Button {
                        onSelect(mins)
                    } label: {
                        Label("Apply \(mins) min to selected items", systemImage: "plus.circle.fill")
                            .font(AppTheme.Typography.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.teal)
                }

                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)

                Text("Presets")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.md)

                // Preset chips
                let columns = [GridItem(.adaptive(minimum: 90, maximum: 180), spacing: AppTheme.Spacing.sm, alignment: .leading)]
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(Self.presets, id: \.minutes) { preset in
                            Button {
                                Haptics.selection()
                                onSelect(preset.minutes)
                            } label: {
                                Text(preset.label)
                                    .font(AppTheme.Typography.callout)
                                    .foregroundStyle(Color.teal)
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                                    .padding(.vertical, AppTheme.Spacing.xs)
                                    .background(Color.teal.opacity(0.10), in: Capsule())
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set estimated duration to \(preset.label) for selected items")
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.md)
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("Set Time Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        onSelect(nil)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
