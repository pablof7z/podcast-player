import SwiftUI

// MARK: - Wiki generate sheet

/// "Compile a page about X" sheet (UX-04 §6e). Drives the conjure flow:
/// user types a topic, watches a 2-second "thinking" UI, receives a
/// fixture page that demonstrates the eventual rendered shape.
///
/// In lane 7 the actual `WikiGenerator` call is stubbed; the sheet
/// returns a fixture page so the surrounding UX is reviewable. A live
/// build wires `client: .live(apiKey:)` through `WikiGenerator` and
/// awaits a real compile.
struct WikiGenerateSheet: View {

    let scope: WikiHomeViewModel.ScopeFilter

    /// Called once the (mocked) compile completes with the new page.
    var onCompile: (WikiPage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topic: String = ""
    @State private var isCompiling = false
    @State private var phase: Phase = .input

    enum Phase: Equatable {
        case input
        case searching
        case drafting
        case resolving
        case done(WikiPage)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                inputField
                phaseDisplay
                Spacer()
                actionRow
            }
            .padding(20)
            .navigationTitle("Compile a page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCompiling)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topic")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            TextField("e.g. mitochondrial uncoupling", text: $topic)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title3)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
                .disabled(isCompiling)
        }
    }

    @ViewBuilder
    private var phaseDisplay: some View {
        switch phase {
        case .input:
            Text("Compiling reads your transcripts, drafts a page, and verifies every claim before it lands.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        case .searching:
            phaseLine(symbol: "magnifyingglass", label: "Searching transcripts…", active: true)
        case .drafting:
            VStack(alignment: .leading, spacing: 10) {
                phaseLine(symbol: "checkmark", label: "Searched transcripts", active: false)
                phaseLine(symbol: "doc.text", label: "Drafting definition…", active: true)
            }
        case .resolving:
            VStack(alignment: .leading, spacing: 10) {
                phaseLine(symbol: "checkmark", label: "Searched transcripts", active: false)
                phaseLine(symbol: "checkmark", label: "Drafted definition", active: false)
                phaseLine(symbol: "quote.bubble", label: "Resolving citations…", active: true)
            }
        case .done(let page):
            doneCard(page: page)
        }
    }

    private func phaseLine(symbol: String, label: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: active)
            Text(label)
                .font(.callout)
                .foregroundStyle(active ? .primary : .secondary)
        }
    }

    private func doneCard(page: WikiPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.34))
                Text("Page compiled")
                    .font(.headline)
            }
            Text(page.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
            Text(page.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 12) {
                Label("\(page.allClaims.count) claims", systemImage: "text.alignleft")
                Label(
                    "\(page.allClaims.flatMap(\.citations).count) citations",
                    systemImage: "quote.bubble"
                )
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var actionRow: some View {
        HStack {
            if case .done(let page) = phase {
                Button {
                    onCompile(page)
                    dismiss()
                } label: {
                    Label("Read the page", systemImage: "book")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await runCompile() }
                } label: {
                    Label("Compile", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || isCompiling)
            }
        }
    }

    // MARK: - Mock compile

    /// Runs the staged "compile" animation and returns a fixture page.
    /// Total runtime ≈ 2 seconds, matching the lane-7 brief.
    @MainActor
    private func runCompile() async {
        isCompiling = true
        phase = .searching
        try? await Task.sleep(nanoseconds: 700_000_000)
        phase = .drafting
        try? await Task.sleep(nanoseconds: 700_000_000)
        phase = .resolving
        try? await Task.sleep(nanoseconds: 600_000_000)

        let page = makeFixturePage(for: topic)
        phase = .done(page)
        isCompiling = false
    }

    /// Builds a topic page that mirrors the requested topic. Pulls bits
    /// from `WikiMockFixture.ozempicTopic` so the rendered surface
    /// looks plausible end-to-end.
    private func makeFixturePage(for rawTopic: String) -> WikiPage {
        let trimmed = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : trimmed
        let scopeValue: WikiScope = {
            switch scope {
            case .global: .global
            case .podcast(let id): .podcast(id)
            }
        }()
        var template = WikiMockFixture.ozempicTopic
        template.id = UUID()
        template.title = title
        template.slug = WikiPage.normalize(slug: title)
        template.summary = "Synthesized from \(template.allClaims.flatMap(\.citations).count) cited spans across your library."
        template.scope = scopeValue
        template.generatedAt = Date()
        template.compileRevision = 1
        template.confidence = 0.62
        return template
    }
}
