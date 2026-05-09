import SwiftUI

struct LLMSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @ObservedObject private var ledger = CostLedger.shared
    @State private var agentSelectorPresented = false
    @State private var memorySelectorPresented = false
    @State private var embeddingsSelectorPresented = false
    @State private var catalog = OpenRouterModelSelectorViewModel()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            List {
                modelsSection
                usageSection
                connectionSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Language Models")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await catalog.loadIfNeeded()
            backfillModelNames()
        }
        .sheet(isPresented: $agentSelectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(selectedModelID: agentModelBinding, selectedModelName: agentModelNameBinding, role: "Agent")
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $memorySelectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(selectedModelID: memoryModelBinding, selectedModelName: memoryModelNameBinding, role: "Memory Compilation")
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $embeddingsSelectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(selectedModelID: embeddingsModelBinding, selectedModelName: embeddingsModelNameBinding, role: "Embeddings")
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var modelsSection: some View {
        Section {
            modelRow(
                icon: "brain.head.profile",
                tint: .orange,
                role: "Agent",
                modelID: store.state.settings.llmModel,
                modelName: store.state.settings.llmModelName
            ) {
                agentSelectorPresented = true
            }
            ModelPreviewCard(model: catalogModel(for: store.state.settings.llmModel))

            modelRow(
                icon: "memories",
                tint: .purple,
                role: "Memory Compilation",
                modelID: store.state.settings.memoryCompilationModel,
                modelName: store.state.settings.memoryCompilationModelName
            ) {
                memorySelectorPresented = true
            }
            ModelPreviewCard(model: catalogModel(for: store.state.settings.memoryCompilationModel))

            modelRow(
                icon: "rectangle.stack.fill.badge.person.crop",
                tint: .blue,
                role: "Embeddings",
                modelID: store.state.settings.embeddingsModel,
                modelName: store.state.settings.embeddingsModelName
            ) {
                embeddingsSelectorPresented = true
            }
            ModelPreviewCard(model: catalogModel(for: store.state.settings.embeddingsModel))
        } header: {
            Text("Model Roles")
        } footer: {
            Text("Each role can use a different provider and model. Agent runs during conversations; Memory Compilation and Embeddings support the knowledge pipeline.")
        }
    }

    private var usageSection: some View {
        Section("Usage") {
            NavigationLink {
                UsageCostSettingsView()
            } label: {
                SettingsRow(
                    icon: "dollarsign.circle.fill",
                    tint: .green,
                    title: "Usage & Cost",
                    value: usageSummary
                )
            }
        }
    }

    private var connectionSection: some View {
        Section("Providers") {
            NavigationLink {
                OpenRouterSettingsView()
            } label: {
                SettingsRow(
                    icon: "key.viewfinder",
                    tint: .indigo,
                    title: "OpenRouter",
                    value: openRouterStatus
                )
            }

            NavigationLink {
                OllamaSettingsView()
            } label: {
                SettingsRow(
                    icon: "cloud.fill",
                    tint: .green,
                    title: "Ollama Cloud",
                    value: ollamaStatus
                )
            }
        }
    }

    // MARK: - Row helper

    private func modelRow(icon: String, tint: Color, role: String, modelID: String, modelName: String, onTap: @escaping () -> Void) -> some View {
        let displayName = displayName(modelID: modelID, modelName: modelName)
        return Button(action: onTap) {
            SettingsRow(
                icon: icon,
                tint: tint,
                title: role,
                subtitle: displayName
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(role), \(displayName)")
        .accessibilityHint("Opens model selector")
    }

    // MARK: - Bindings

    private var agentModelBinding: Binding<String> {
        Binding(
            get: { store.state.settings.llmModel },
            set: { v in var s = store.state.settings; s.llmModel = v; store.updateSettings(s) }
        )
    }

    private var agentModelNameBinding: Binding<String> {
        Binding(
            get: { store.state.settings.llmModelName },
            set: { v in var s = store.state.settings; s.llmModelName = v; store.updateSettings(s) }
        )
    }

    private var memoryModelBinding: Binding<String> {
        Binding(
            get: { store.state.settings.memoryCompilationModel },
            set: { v in var s = store.state.settings; s.memoryCompilationModel = v; store.updateSettings(s) }
        )
    }

    private var memoryModelNameBinding: Binding<String> {
        Binding(
            get: { store.state.settings.memoryCompilationModelName },
            set: { v in var s = store.state.settings; s.memoryCompilationModelName = v; store.updateSettings(s) }
        )
    }

    private var embeddingsModelBinding: Binding<String> {
        Binding(
            get: { store.state.settings.embeddingsModel },
            set: { v in var s = store.state.settings; s.embeddingsModel = v; store.updateSettings(s) }
        )
    }

    private var embeddingsModelNameBinding: Binding<String> {
        Binding(
            get: { store.state.settings.embeddingsModelName },
            set: { v in var s = store.state.settings; s.embeddingsModelName = v; store.updateSettings(s) }
        )
    }

    // MARK: - Helpers

    /// Returns the stored human-readable name when available, falling back to
    /// the path-stripped model ID slug for backward compatibility.
    private func displayName(modelID: String, modelName: String) -> String {
        Settings.modelDisplayName(modelID: modelID, modelName: modelName)
    }

    /// Backfills stored model names from the catalog for existing installs
    /// that have a model ID but no persisted name.
    private func backfillModelNames() {
        var s = store.state.settings
        var changed = false
        if s.llmModelName.isEmpty, let match = catalog.models.first(where: { $0.id == s.llmModel }) {
            s.llmModelName = match.name
            changed = true
        }
        if s.memoryCompilationModelName.isEmpty, let match = catalog.models.first(where: { $0.id == s.memoryCompilationModel }) {
            s.memoryCompilationModelName = match.name
            changed = true
        }
        if s.embeddingsModelName.isEmpty, let match = catalog.models.first(where: { $0.id == s.embeddingsModel }) {
            s.embeddingsModelName = match.name
            changed = true
        }
        if changed { store.updateSettings(s) }
    }

    private var usageSummary: String? {
        guard !ledger.records.isEmpty else { return nil }
        let total = ledger.records.reduce(0) { $0 + $1.costUSD }
        return "\(ledger.records.count) calls · \(CostFormatter.usd(total))"
    }

    private var openRouterStatus: String {
        switch store.state.settings.openRouterCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }

    private var ollamaStatus: String {
        switch store.state.settings.ollamaCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }

    private func catalogModel(for modelID: String) -> OpenRouterModelOption? {
        let id = modelID.trimmed
        guard !id.isEmpty else { return nil }
        return catalog.models.first { $0.id == id }
    }

    // MARK: - ModelPreviewCard

    /// A compact info strip shown beneath each model-role row.
    /// Shows context-window size, pricing tier, and key capability badges.
    /// Renders nothing when the model hasn't been loaded from the catalog yet.
    private struct ModelPreviewCard: View {

        private enum Layout {
            static let chipCornerRadius: CGFloat = 6
            static let chipPaddingH: CGFloat = 6
            static let chipPaddingV: CGFloat = 3
            static let rowSpacing: CGFloat = 6
            static let chipIconSize: CGFloat = 9
            static let chipLabelSize: CGFloat = 11
            static let chipInnerSpacing: CGFloat = 3
        }

        let model: OpenRouterModelOption?

        var body: some View {
            if let model {
                HStack(spacing: Layout.rowSpacing) {
                    if let ctx = model.contextLength {
                        chip(contextLabel(ctx), icon: "text.alignleft", color: .blue)
                    }
                    chip(model.compactPricing, icon: "dollarsign", color: pricingColor(model))
                    if model.supportsTools {
                        chip("Tools", icon: "wrench.and.screwdriver", color: .teal)
                    }
                    if model.supportsReasoning {
                        chip("Reasoning", icon: "brain", color: .purple)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, SettingsRow.contentLeadingInset)
                .padding(.bottom, AppTheme.Spacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityDescription(model))
            }
        }

        private func chip(_ label: String, icon: String, color: Color) -> some View {
            HStack(spacing: Layout.chipInnerSpacing) {
                Image(systemName: icon)
                    .font(.system(size: Layout.chipIconSize, weight: .semibold))
                Text(label)
                    .font(.system(size: Layout.chipLabelSize, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, Layout.chipPaddingH)
            .padding(.vertical, Layout.chipPaddingV)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Layout.chipCornerRadius, style: .continuous))
        }

        private func contextLabel(_ tokens: Int) -> String {
            if tokens >= 1_000_000 { return "\(tokens / 1_000_000)M ctx" }
            if tokens >= 1_000     { return "\(tokens / 1_000)K ctx" }
            return "\(tokens) ctx"
        }

        private func pricingColor(_ model: OpenRouterModelOption) -> Color {
            if model.isFree { return .green }
            if let cost = model.promptCostPerMillion, cost < 1 { return .secondary }
            return .orange
        }

        private func accessibilityDescription(_ model: OpenRouterModelOption) -> String {
            var parts: [String] = []
            if let ctx = model.contextLength { parts.append(contextLabel(ctx)) }
            parts.append(model.compactPricing)
            if model.supportsTools     { parts.append("supports tools") }
            if model.supportsReasoning { parts.append("supports reasoning") }
            return parts.joined(separator: ", ")
        }
    }
}
