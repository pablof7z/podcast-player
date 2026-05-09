import SwiftUI
import UniformTypeIdentifiers

// MARK: - OPMLImportPhase

/// Lifecycle of the OPML import sheet. The sheet rotates the user through
/// three single-purpose screens — `pick`, `review`, `progress` — rather than
/// stacking everything at once.
enum OPMLImportPhase: Equatable {
    case pick
    case review(parsed: [PodcastSubscription])
    case progress(completed: Int, total: Int, errors: [OPMLImportRowError])
    case done(imported: Int, skipped: Int, errors: [OPMLImportRowError])
}

// MARK: - OPMLImportRowError

/// Per-row import failure surfaced under the progress bar. We track the feed
/// URL plus the human-readable reason so the user can copy the URL out and
/// retry manually if a single feed in their OPML is broken.
struct OPMLImportRowError: Identifiable, Equatable {
    let id = UUID()
    let feedURL: URL
    let title: String
    let message: String
}

// MARK: - OPMLImportSheet

/// File-importer + paste-OPML-text-mode + per-row enrichment progress.
///
/// **Glass usage:** the entire sheet is a structural Liquid Glass surface
/// (per the lane brief: "structural glass on the nav chrome and the OPML
/// import sheet only"). Cards inside the sheet remain matte; only the sheet
/// container glows.
struct OPMLImportSheet: View {

    let store: AppStateStore
    let onDismiss: () -> Void

    @State private var phase: OPMLImportPhase = .pick
    @State private var pastedText: String = ""
    @State private var fileImporterShown: Bool = false
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            content
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.ultraThinMaterial)
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
        case .pick:
            pickPhase
        case .review(let parsed):
            reviewPhase(parsed: parsed)
        case .progress(let c, let t, let errors):
            progressPhase(completed: c, total: t, errors: errors)
        case .done(let imported, let skipped, let errors):
            donePhase(imported: imported, skipped: skipped, errors: errors)
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

            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Review phase

    private func reviewPhase(parsed: [PodcastSubscription]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("\(parsed.count) feeds parsed")
                    .font(AppTheme.Typography.title)
                Text("Review and confirm. Existing subscriptions will be skipped.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ForEach(parsed) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(AppTheme.Typography.headline)
                                .lineLimit(1)
                            Text(entry.feedURL.absoluteString)
                                .font(AppTheme.Typography.monoCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
            }
            .frame(maxHeight: 240)

            Button {
                Haptics.medium()
                Task { await runImport(entries: parsed) }
            } label: {
                Label("Import \(parsed.count) shows", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - Progress phase

    private func progressPhase(
        completed: Int,
        total: Int,
        errors: [OPMLImportRowError]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Importing your library")
                .font(AppTheme.Typography.title)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
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

            errorList(errors)

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
        }
    }

    // MARK: - Done phase

    private func donePhase(
        imported: Int,
        skipped: Int,
        errors: [OPMLImportRowError]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Import complete")
                    .font(AppTheme.Typography.title)
                Text("\(imported) added, \(skipped) skipped, \(errors.count) failed.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            errorList(errors)

            Button {
                Haptics.success()
                onDismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
            }
            .buttonStyle(.glassProminent)
        }
    }

    // MARK: - Shared error list

    @ViewBuilder
    private func errorList(_ errors: [OPMLImportRowError]) -> some View {
        if !errors.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Errors")
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(errors) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(AppTheme.Typography.caption.weight(.semibold))
                        Text(row.message)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Corner.sm, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
                }
            }
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
        switch result {
        case .failure(let error):
            parseError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                try parseAndAdvance(data: data)
            } catch {
                parseError = "Couldn't read the OPML file: \(error.localizedDescription)"
            }
        }
    }

    private func handlePastedText() {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8)
        else { return }
        do {
            try parseAndAdvance(data: data)
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func parseAndAdvance(data: Data) throws {
        let entries = try OPMLImport().parseOPML(data: data)
        guard !entries.isEmpty else {
            parseError = "No feeds found in that OPML."
            return
        }
        parseError = nil
        withAnimation { phase = .review(parsed: entries) }
    }

    private func runImport(entries: [PodcastSubscription]) async {
        let total = entries.count
        var errors: [OPMLImportRowError] = []
        var imported = 0
        var skipped = 0
        let service = SubscriptionService(store: store)
        withAnimation { phase = .progress(completed: 0, total: total, errors: errors) }
        for (index, entry) in entries.enumerated() {
            do {
                if let _ = try await service.adopt(opmlEntry: entry) {
                    imported += 1
                } else {
                    skipped += 1
                }
            } catch let addError as SubscriptionService.AddError {
                errors.append(.init(
                    feedURL: entry.feedURL,
                    title: entry.title,
                    message: addError.localizedDescription
                ))
            } catch {
                errors.append(.init(
                    feedURL: entry.feedURL,
                    title: entry.title,
                    message: error.localizedDescription
                ))
            }
            withAnimation {
                phase = .progress(completed: index + 1, total: total, errors: errors)
            }
        }
        Haptics.success()
        withAnimation {
            phase = .done(imported: imported, skipped: skipped, errors: errors)
        }
    }
}
