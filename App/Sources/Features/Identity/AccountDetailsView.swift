import SwiftUI
import CryptoKit

// MARK: - AccountDetailsView
//
// Per identity-05-synthesis §4.8. Power users go here for hex, fingerprint,
// mode, and (eventually) relay status. MVP defers the audit log + per-relay
// RTT table — the page is sized to grow into them.

struct AccountDetailsView: View {

    @Environment(UserIdentityStore.self) private var identity
    @State private var npubCopied = false
    @State private var hexCopied = false
    @State private var fpCopied = false
    @State private var qrPresented = false

    var body: some View {
        Form {
            Section("Public key") {
                kvRow(label: "npub", value: identity.npub ?? "—", isCopied: $npubCopied)
                kvRow(label: "hex", value: identity.publicKeyHex ?? "—", isCopied: $hexCopied)
                kvRow(label: "fp", value: fingerprintLine, isCopied: $fpCopied)
            }
            Section("Signer") {
                detailLine(label: "mode", value: modeLabel)
                detailLine(label: "source", value: sourceLine)
            }
            Section("Profile") {
                Text("Profile sync runs in the background. A republish trigger lands with Slice B.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Button {
                    qrPresented = true
                } label: {
                    Label("Show as QR", systemImage: "qrcode")
                }
                .disabled(identity.npub == nil)
            }
        }
        .navigationTitle("Account details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $qrPresented) {
            if let npub = identity.npub {
                AgentIdentityQRView(npub: npub, name: "Account ID")
            }
        }
    }

    // MARK: - Rows

    private func kvRow(label: String, value: String, isCopied: Binding<Bool>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(AppTheme.Typography.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(AppTheme.Typography.monoCaption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Spacer(minLength: AppTheme.Spacing.xs)
            Button {
                copyToClipboard(value, isCopied: isCopied, haptic: { Haptics.success() })
                UIAccessibility.post(notification: .announcement, argument: "Copied")
            } label: {
                Image(systemName: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                    .font(AppTheme.Typography.caption)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .disabled(value == "—")
            .accessibilityLabel("Copy \(label)")
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(AppTheme.Typography.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(AppTheme.Typography.body)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: - Derived values

    private var modeLabel: String {
        switch identity.mode {
        case .remoteSigner: return "Bunker via Amber"
        case .localKey:     return "Local Key"
        case .none:         return "—"
        }
    }

    /// Heuristic source line. Until Slice B exposes the on-disk origin marker
    /// directly, we surface a coarse description.
    private var sourceLine: String {
        switch identity.mode {
        case .remoteSigner: return "remote signer"
        case .localKey:     return "local key on this device"
        case .none:         return "—"
        }
    }

    /// First 16 hex chars of SHA-256(pubkeyHex). Stable, short, useful for
    /// distinguishing accounts when multi-account lands in v2.
    private var fingerprintLine: String {
        guard let hex = identity.publicKeyHex,
              let data = hex.data(using: .utf8) else { return "—" }
        let digest = SHA256.hash(data: data)
        let prefix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(prefix)"
    }
}
