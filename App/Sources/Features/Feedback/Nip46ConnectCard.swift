import SwiftUI

/// "Add a remote signer" card embedded inside `UserIdentityView`. Lets the user paste
/// a `bunker://` URI, shows live connection state, and (when connected) confirms the
/// user's pubkey + offers a disconnect button.
struct Nip46ConnectCard: View {
    @Environment(UserIdentityStore.self) private var identity
    @Binding var bunkerInput: String
    @Binding var isConnectingRemote: Bool
    let connect: () async -> Void
    let disconnect: () async -> Void
    @FocusState private var bunkerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            header
            switch identity.remoteSignerState {
            case .idle:
                if identity.isRemoteSigner {
                    connectedRow
                } else {
                    inputRow
                }
            case .connecting:
                statusRow(text: "Connecting to bunker…", isWorking: true)
            case .reconnecting:
                statusRow(text: "Reconnecting…", isWorking: true)
            case .connected(let userPub):
                connectedRow(pubkeyHex: userPub)
            case .failed(let message):
                inputRow
                Text(message)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
            }
            footnote
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("NIP-46 Remote Signer", systemImage: "link.icloud.fill")
                .font(AppTheme.Typography.headline)
            Spacer()
            if identity.isRemoteSigner, case .connected = identity.remoteSignerState {
                Text("Connected")
                    .font(AppTheme.Typography.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Paste a bunker URI from Amber, nsec.app, or nsecBunker.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            TextField("bunker://…?relay=wss://…&secret=…", text: $bunkerInput, axis: .vertical)
                .lineLimit(1...4)
                .font(AppTheme.Typography.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($bunkerFocused)
                .padding(AppTheme.Spacing.sm)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.sm))
                .dismissKeyboardToolbar()
            Button {
                Task { await connect() }
            } label: {
                Label(isConnectingRemote ? "Connecting…" : "Connect bunker", systemImage: "link")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(bunkerInput.trimmed.isEmpty || isConnectingRemote)
        }
    }

    // MARK: - Status row

    private func statusRow(text: String, isWorking: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if isWorking { ProgressView().controlSize(.small) }
            Text(text)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connected row

    private var connectedRow: some View {
        connectedRow(pubkeyHex: identity.publicKeyHex ?? "")
    }

    private func connectedRow(pubkeyHex: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let bytes = Data(hexString: pubkeyHex), bytes.count == 32 {
                let npub = Bech32.encode(hrp: "npub", data: bytes)
                Text("Signing as")
                    .font(AppTheme.Typography.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(npub)
                    .font(AppTheme.Typography.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Button(role: .destructive) {
                Task { await disconnect() }
            } label: {
                Label("Disconnect bunker", systemImage: "link.badge.minus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var footnote: some View {
        Text("Your private key never touches this device — every signature happens inside the bunker.")
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(.tertiary)
    }
}
