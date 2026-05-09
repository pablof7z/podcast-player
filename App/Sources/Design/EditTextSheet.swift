import SwiftUI

/// A modal sheet for editing a single block of text.
///
/// Presents a `TextEditor` with a title, a `Cancel` button that discards
/// changes, and a `Save` button that calls `onSave` with the trimmed text.
/// The Save button is disabled when the trimmed draft is empty or unchanged.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showEdit) {
///     EditTextSheet(title: "Edit Memory", initialText: memory.content) { newText in
///         store.updateAgentMemory(memory.id, content: newText)
///     }
/// }
/// ```
struct EditTextSheet: View {

    // MARK: - Layout constants

    private enum Layout {
        /// Minimum height for the TextEditor so short entries don't feel cramped.
        static let editorMinHeight: CGFloat = 120
        /// Corner radius of the TextEditor glass surface.
        static let editorCornerRadius: CGFloat = AppTheme.Corner.lg
    }

    // MARK: - Properties

    let title: String
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    TextEditor(text: $draft)
                        .focused($editorFocused)
                        .font(AppTheme.Typography.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: Layout.editorMinHeight)
                        .padding(AppTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(
                                cornerRadius: Layout.editorCornerRadius,
                                style: .continuous
                            )
                            .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.md)

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.trimmed)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(saveDisabled)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            draft = initialText
            editorFocused = true
        }
    }

    // MARK: - Helpers

    private var saveDisabled: Bool {
        draft.isBlank || draft.trimmed == initialText.trimmed
    }
}
