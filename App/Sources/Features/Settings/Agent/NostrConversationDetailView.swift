import SwiftUI
import UIKit

/// Full transcript of a single Nostr conversation root. Mirrors the
/// rendering style of the in-app chat history but with NIP-10 metadata
/// (no titles — Nostr threads don't carry one by default).
struct NostrConversationDetailView: View {
    let conversation: NostrConversationRecord
    @State private var showExportSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                ForEach(conversation.turns, id: \.eventID) { turn in
                    NostrTurnBubble(turn: turn)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.selection()
                    showExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export events")
            }
        }
        .sheet(isPresented: $showExportSheet) {
            NostrConversationExportSheet(jsonlContent: generateJSONL())
        }
    }

    private func generateJSONL() -> String {
        conversation.turns
            .compactMap { $0.rawEventJSON }
            .joined(separator: "\n")
    }
}

// MARK: - Bubble

private struct NostrTurnBubble: View {
    let turn: NostrConversationTurn

    var body: some View {
        HStack {
            if turn.direction == .outgoing { Spacer(minLength: AppTheme.Layout.bubbleSpacer) }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(turn.content)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(turn.direction == .outgoing ? Color.white : Color.primary)
                Text(timestamp)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(turn.direction == .outgoing ? Color.white.opacity(0.8) : Color.secondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Corner.bubble, style: .continuous)
                    .fill(turn.direction == .outgoing
                        ? AppTheme.Tint.agentSurface
                        : Color(.secondarySystemBackground))
            )
            if turn.direction == .incoming { Spacer(minLength: AppTheme.Layout.bubbleSpacer) }
        }
    }

    private var timestamp: String {
        turn.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Export sheet

struct NostrConversationExportSheet: View {
    let jsonlContent: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var fileURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.md) {
                HStack {
                    Text("Events (JSONL)")
                        .font(AppTheme.Typography.headline)
                    Spacer()
                    Button(action: copyToClipboard) {
                        Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                            .foregroundStyle(copied ? AppTheme.Tint.success : Color.accentColor)
                    }
                    .disabled(copied)
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                ScrollView {
                    Text(jsonlContent.isEmpty ? "(no exportable events)" : jsonlContent)
                        .font(AppTheme.Typography.mono)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                                .fill(AppTheme.Tint.surfaceMuted)
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)
                }
                .frame(maxHeight: .infinity)

                shareButton
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
            .padding(.vertical, AppTheme.Spacing.md)
            .navigationTitle("Export Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { fileURL = writeTempFile() }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = fileURL {
            ShareLink(item: url, subject: Text("Conversation Events"), label: { shareLabel })
        } else {
            ShareLink(item: jsonlContent, subject: Text("Conversation Events"), label: { shareLabel })
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .cornerRadius(AppTheme.Corner.md)
    }

    private func writeTempFile() -> URL? {
        let suffix = UUID().uuidString.prefix(8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-\(suffix).jsonl")
        do {
            try jsonlContent.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = jsonlContent
        copied = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
