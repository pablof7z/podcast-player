import SwiftUI

// MARK: - BulkTagPickerSheet

/// Sheet that lets the user pick an existing tag or type a new one to apply
/// to all currently-selected items in bulk.
///
/// Existing tags are shown as tappable chips; a text field at the top lets
/// the user type a new tag if none of the existing ones are suitable.
struct BulkTagPickerSheet: View {

    let existingTags: [String]
    var onSelect: (String) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedDraft: String { draft.lowercased().trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool { !trimmedDraft.isEmpty }

    /// Tags that match the current draft text, used to provide live filtering
    /// when the user is typing a new tag that might already exist.
    private var filteredTags: [String] {
        guard !trimmedDraft.isEmpty else { return existingTags }
        return existingTags.filter { $0.localizedCaseInsensitiveContains(trimmedDraft) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // --- New tag input ---
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("New tag…", text: $draft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($fieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            guard canSubmit else { return }
                            onSelect(trimmedDraft)
                        }
                    if !draft.isEmpty {
                        Button {
                            draft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear tag text")
                    }
                }
                .padding(AppTheme.Spacing.sm)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous))
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)

                if canSubmit {
                    // Quick-apply button for the typed draft
                    Button {
                        onSelect(trimmedDraft)
                    } label: {
                        Label("Apply \"\(trimmedDraft)\" to selected items", systemImage: "plus.circle.fill")
                            .font(AppTheme.Typography.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                if !filteredTags.isEmpty {
                    Divider()
                        .padding(.horizontal, AppTheme.Spacing.md)

                    Text(trimmedDraft.isEmpty ? "Existing tags" : "Matching tags")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Spacing.md)

                    // Wrap-flow chip grid — FlowLayout fallback using a simple
                    // wrapping HStack approach via LazyVGrid.
                    tagChipGrid
                }

                if existingTags.isEmpty && !canSubmit {
                    Spacer()
                    ContentUnavailableView {
                        Label("No tags yet", systemImage: "tag")
                    } description: {
                        Text("Type a tag name above to create one and apply it to the selected items.")
                    }
                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Tag chip grid

    private var tagChipGrid: some View {
        // Two-column grid gives a natural chip-like layout without a custom
        // flow-layout implementation; chips are left-aligned via a flexible column.
        let columns = [
            GridItem(.adaptive(minimum: 80, maximum: 200), spacing: AppTheme.Spacing.sm, alignment: .leading)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(filteredTags, id: \.self) { tag in
                    Button {
                        Haptics.selection()
                        onSelect(tag)
                    } label: {
                        Text("#\(tag)")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply tag \(tag) to selected items")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }
}
