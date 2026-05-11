import SwiftUI

struct AIProvidersSettingsView: View {
    @Environment(AppStateStore.self) private var store
    @ObservedObject private var ledger = CostLedger.shared

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            List {
                providersSection
                usageSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var providersSection: some View {
        Section {
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
                ElevenLabsSettingsView()
            } label: {
                SettingsRow(
                    icon: "waveform",
                    tint: AppTheme.Brand.elevenLabsTint,
                    title: "ElevenLabs",
                    value: elevenLabsStatus
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
        } header: {
            Text("Connections")
        } footer: {
            Text("Connect provider keys here. Choose which provider and model each role uses in Models.")
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

    // MARK: - Derived

    private var settings: Settings { store.state.settings }

    private var openRouterStatus: String {
        switch settings.openRouterCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }

    private var elevenLabsStatus: String {
        switch settings.elevenLabsCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }

    private var ollamaStatus: String {
        switch settings.ollamaCredentialSource {
        case .byok:   return "BYOK"
        case .manual: return "Manual"
        case .none:   return "Not set up"
        }
    }

    private var usageSummary: String? {
        guard !ledger.records.isEmpty else { return nil }
        let total = ledger.records.reduce(0) { $0 + $1.costUSD }
        return "\(ledger.records.count) calls · \(CostFormatter.usd(total))"
    }
}

struct AISettingsView: View {
    var body: some View {
        AIProvidersSettingsView()
    }
}
