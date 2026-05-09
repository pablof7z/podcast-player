import SwiftUI
import UniformTypeIdentifiers

// MARK: - OPMLImportPhase

/// Lifecycle of the OPML import sheet. The sheet rotates the user
/// through three single-purpose screens — `pick`, `review`, `progress` —
/// rather than stacking everything at once. Phase changes are animated
/// with `AppTheme.Animation.spring`.
enum OPMLImportPhase: Equatable {
    case pick
    case review(parsedShowCount: Int)
    case progress(completed: Int, total: Int)
}

// MARK: - OPMLImportSheet

/// File-importer + paste-OPML-text-mode + first-refresh progress.
///
/// **Glass usage:** the entire sheet is a structural Liquid Glass
/// surface (per the lane brief: "structural glass on the nav chrome and
/// the OPML import sheet only"). Cards inside the sheet remain matte;
/// only the sheet container glows.
///
/// **Mock behavior:** the sheet does not parse real OPML. It pretends
/// to count feeds, then calls `LibraryMockStore.importMockOPML` which
/// appends a few canned subscriptions. Lane 2 swaps in the real parser.
struct OPMLImportSheet: View {

    let store: LibraryMockStore
    let onDismiss: () -> Void

    @State private var phase: OPMLImportPhase = .pick
    @State private var pastedText: String = ""
    @State private var fileImporterShown: Bool = false
    @State private var transcribeNew: Bool = true

    var body: some View {
        NavigationStack {
            content
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.ultraThinMaterial)        // Liquid Glass T1 sheet
                .toolbar { toolbarContent }
                .navigationTitle("Import from OPML")
                .navigationBarTitleDisplayMode(.inline)
                .animation(AppTheme.Animation.spring, value: phase)
        }
        .fileImporter(
            isPresented: $fileImporterShown,
            allowedContentTypes: [opmlContentType, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .pick:                  pickPhase
        case .review(let count):     reviewPhase(parsedShowCount: count)
        case .progress(let c, let t): progressPhase(completed: c, total: t)
        }
    }

    // MARK: - Pick phase

    private var pickPhase: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Bring your shows over.")
                .font(AppTheme.Typography.title)
            Text("Import an OPML file from another podcast app, or paste OPML text below.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(.secondary)

            Button {
                Haptics.light()
                fileImporterShown = true
            } label: {
                Label("Choose OPML file…", systemImage: "doc.text.below.ecg")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .buttonStyle(.glassProminent)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Or paste OPML text")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pastedText)
                    .font(AppTheme.Typography.monoCaption)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Button {
                    Haptics.light()
                    handlePastedText()
                } label: {
                    Text("Parse pasted OPML")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                }
                .buttonStyle(.bordered)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Review phase

    @ViewBuilder
    private func reviewPhase(parsedShowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("\(parsedShowCount) feeds parsed")
                    .font(AppTheme.Typography.title)
                Text("Review and confirm. Existing subscriptions will be skipped.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Toggle(isOn: $transcribeNew) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-transcribe new shows")
                            .font(AppTheme.Typography.headline)
                        Text("Recommended; can be paused later.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppTheme.Tint.agentSurface)
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            Button {
                Haptics.medium()
                Task { await runImport(total: parsedShowCount) }
            } label: {
                Label("Import \(parsedShowCount) shows", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .buttonStyle(.glassProminent)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Progress phase

    private func progressPhase(completed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Importing your library")
                .font(AppTheme.Typography.title)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(AppTheme.Tint.agentSurface)
                Text("\(completed) / \(total) shows fetched")
                    .font(AppTheme.Typography.monoCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Text("This continues in the background. You can close this sheet at any time.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)

            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Text("Run in background")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close import")
        }
    }

    // MARK: - Actions

    private var opmlContentType: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, urls.first != nil else { return }
        // Lane 3 mock: pretend the file contained 12 shows.
        withAnimation { phase = .review(parsedShowCount: 12) }
    }

    private func handlePastedText() {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Lane 3 mock: count newlines as a proxy for feed count, clamped.
        let approx = max(1, min(64, trimmed.split(separator: "\n").count / 4))
        withAnimation { phase = .review(parsedShowCount: approx) }
    }

    private func runImport(total: Int) async {
        // Step the progress through a small canned animation so the
        // progress affordance reads as alive during dev review.
        for completed in 0...total {
            withAnimation { phase = .progress(completed: completed, total: total) }
            try? await Task.sleep(for: .milliseconds(80))
        }
        // Push 3 imported subscriptions into the store at the end.
        await store.importMockOPML(addingShows: 3)
        Haptics.success()
        onDismiss()
    }
}
