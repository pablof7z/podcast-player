import SwiftUI

// MARK: - Tags section

/// Self-contained tags editor used inside `ItemDetailSheet`.
///
/// Renders the current tag chips and an add-tag text field.
/// Mutations route through `AppStateStore` directly.
struct ItemDetailTagsSection: View {
    let item: Item

    @Environment(AppStateStore.self) private var store

    @State private var tagDraft: String = ""
    @FocusState private var tagFieldFocused: Bool

    private enum Layout {
        static let metaIconWidth: CGFloat = 20
        /// Point size of the remove-tag xmark icon inside each chip.
        static let removeIconSize: CGFloat = 12
    }

    var body: some View {
        Section {
            if !item.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(item.tags, id: \.self) { tag in
                            tagChip(tag: tag)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
                .listRowInsets(.init(
                    top: 0,
                    leading: AppTheme.Spacing.md,
                    bottom: 0,
                    trailing: AppTheme.Spacing.md
                ))
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.metaIconWidth)
                    .accessibilityHidden(true)
                TextField("Add tag…", text: $tagDraft)
                    .font(AppTheme.Typography.body)
                    .focused($tagFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTagDraft() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !tagDraft.isEmpty {
                    Button {
                        commitTagDraft()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add tag")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(AppTheme.Animation.springFast, value: tagDraft.isEmpty)
        } header: {
            Text("Tags")
        } footer: {
            Text("Tags group related items and enable quick filtering from Home.")
        }
    }

    // MARK: - Private

    private func tagChip(tag: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("#\(tag)")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.accentColor)
            Button {
                store.removeTag(tag, from: item.id)
                Haptics.selection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Layout.removeIconSize))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
    }

    private func commitTagDraft() {
        let normalized = tagDraft.lowercased().trimmed
        guard !normalized.isEmpty else { return }
        store.addTag(normalized, to: item.id)
        Haptics.selection()
        tagDraft = ""
    }
}
