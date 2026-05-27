import SwiftUI

struct RelayDetailView: View {
    @Environment(AppStateStore.self) private var store
    let relayURL: String

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("URL", value: relayURL)
                LabeledContent("Role", value: "Primary")
            }
            Section("Roles") {
                ForEach(RelayRoleViewModel.allCases) { role in
                    HStack(spacing: 10) {
                        Image(systemName: role.icon)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        Text(role.rawValue)
                    }
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(URL(string: relayURL)?.host ?? relayURL)
        .navigationBarTitleDisplayMode(.inline)
    }
}
