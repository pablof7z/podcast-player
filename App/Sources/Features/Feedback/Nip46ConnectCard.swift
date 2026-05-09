import SwiftUI
import UIKit

/// "Add a remote signer" card embedded inside `UserIdentityView`. Lets the user paste
/// a `bunker://` URI, shows live connection state, surfaces auth-challenge URLs, and
/// (when connected) confirms the user's pubkey + offers a disconnect button.
struct Nip46ConnectCard: View {
    @Environment(UserIdentityStore.self) private var identity
    @Environment(\.openURL) private var openURL
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
                connectingRow(text: "Connecting to bunker…")
            case .reconnecting:
                connectingRow(text: "Reconnecting…")
            case .awaitingAuthorization(let url):
                authChallengeRow(url: url)
            case .connected(let userPub):
                connectedRow(pubkeyHex: userPub)
            case .failed(let message):
                failedRow(message: message)
            }
            footnote
        }
        .padding(AppTheme.Spacing.md)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Corner.md))
        .onAppear { autoPasteBunkerIfPresent() }
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

    // MARK: - Status rows

    /// In-flight connect / reconnect with an indeterminate spinner. We don't surface a
    /// cancel button here — `disconnectRemoteSigner()` would tear down anyway, and the
    /// transient state usually resolves within a couple of seconds.
    private func connectingRow(text: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Bunker has handed back an auth_url and is waiting for the user to approve in a
    /// browser before sending the real `ack`. Tapping the button opens Safari (or the
    /// bunker's native handler if it's claimed the URL) to the approval page.
    private func authChallengeRow(url: URL) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Your bunker needs you to approve this connection in the browser.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            Button {
                openURL(url)
            } label: {
                Label("Approve in browser", systemImage: "safari.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            Button(role: .destructive) {
                Task { await disconnect() }
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }

    /// Failure state: show the trimmed message + offer a retry that just re-runs `connect`.
    private func failedRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            inputRow
            HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(truncated(message, max: 200))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
            }
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

    // MARK: - Helpers

    /// If the clipboard already holds a `bunker://` URI and the input is empty, prefill it.
    /// Common paste-and-go flow when the user just copied the URI from another app.
    private func autoPasteBunkerIfPresent() {
        guard bunkerInput.trimmed.isEmpty,
              UIPasteboard.general.hasStrings,
              let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.hasPrefix("bunker://") else { return }
        bunkerInput = s
    }

    private func truncated(_ s: String, max: Int) -> String {
        s.count <= max ? s : "\(s.prefix(max))…"
    }
}
