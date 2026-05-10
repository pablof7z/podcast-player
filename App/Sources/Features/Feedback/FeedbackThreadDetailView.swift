import SwiftUI

// MARK: - FeedbackThreadDetailView

struct FeedbackThreadDetailView: View {

    private enum Layout {
        static let imageCornerRadius: CGFloat = 14
        static let imageMaxHeight: CGFloat = 240
        static let closeButtonPadding: CGFloat = 20
        static let closeIconSize: CGFloat = 28
        static let rowPaddingV: CGFloat = 2
        static let summaryBannerPadding: CGFloat = 12
        static let summaryIconSpacing: CGFloat = 10
        static let summaryTextSpacing: CGFloat = 2
        static let composerPaddingH: CGFloat = 12
        static let composerVSpacing: CGFloat = 6
        static let composerCornerRadius: CGFloat = 28
        static let imageBubbleSpacerMin: CGFloat = 60
    }

    let thread: FeedbackThread
    let store: FeedbackStore
    @Environment(UserIdentityStore.self) private var userIdentity

    @State private var replyDraft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var imageFullscreen = false
    @FocusState private var composerFocused: Bool

    private var currentThread: FeedbackThread {
        store.threads.first(where: { $0.id == thread.id }) ?? thread
    }

    private var canSend: Bool {
        !replyDraft.isBlank && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
        }
        .navigationTitle(currentThread.title ?? currentThread.category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if let status = currentThread.statusLabel, !status.isEmpty {
                        FeedbackStatusBadge(status: status)
                    }
                    Menu {
                        Button {
                            UIPasteboard.general.string = currentThread.content
                            Haptics.selection()
                        } label: {
                            Label("Copy text", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Thread options")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            replyComposer
        }
        .fullScreenCover(isPresented: $imageFullscreen) {
            if let image = currentThread.attachedImage {
                imageViewer(image)
            }
        }
    }

    // MARK: - Full-screen image viewer

    private func imageViewer(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                imageFullscreen = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Layout.closeIconSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(Layout.closeButtonPadding)
            }
            .accessibilityLabel("Close image")
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Layout.rowPaddingV) {
                    if let summary = currentThread.summary, !summary.isEmpty {
                        summaryBanner(summary)
                    }

                    // Root message bubble
                    FeedbackBubble(
                        content: currentThread.content,
                        isFromMe: currentThread.authorPubkey == userIdentity.publicKeyHex,
                        createdAt: currentThread.createdAt
                    )
                    .id("root")

                    // Attached screenshot (if any)
                    if let image = currentThread.attachedImage {
                        attachedImageBubble(image)
                    }

                    // Reply bubbles
                    ForEach(currentThread.replies) { reply in
                        FeedbackBubble(
                            content: reply.content,
                            isFromMe: reply.isFromMe,
                            createdAt: reply.createdAt,
                            onQuoteReply: reply.isFromMe ? nil : {
                                quoteReply(reply.content)
                            }
                        )
                        .id(reply.id)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .onChange(of: currentThread.replies.count) { _, _ in
                if let last = currentThread.replies.last {
                    withAnimation(AppTheme.Animation.easeOut) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Attached image bubble

    private func attachedImageBubble(_ image: UIImage) -> some View {
        HStack {
            Spacer(minLength: Layout.imageBubbleSpacerMin)
            Button {
                Haptics.selection()
                imageFullscreen = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: Layout.imageMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.imageCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.imageCornerRadius)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Attached screenshot — tap to expand")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, Layout.rowPaddingV)
    }

    @ViewBuilder
    private func summaryBanner(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: Layout.summaryIconSpacing) {
            Image(systemName: "sparkles")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Layout.summaryTextSpacing) {
                Text("Summary")
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.primary)
            }
        }
        .padding(Layout.summaryBannerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AppTheme.Corner.lg)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: - Reply composer

    private var replyComposer: some View {
        VStack(spacing: Layout.composerVSpacing) {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
            HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                TextField("Reply\u{2026}", text: $replyDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .focused($composerFocused)

                Button {
                    Task { await sendReply() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                        .background(Color.accentColor.opacity(canSend ? 1 : 0.4), in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Send reply")
                .disabled(!canSend)
            }
            .padding(.horizontal, Layout.composerPaddingH)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular, in: .rect(cornerRadius: Layout.composerCornerRadius))
            .padding(.horizontal, Layout.composerPaddingH)
            .padding(.bottom, AppTheme.Spacing.xs)
        }
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: - Quote reply

    private func quoteReply(_ content: String) {
        Haptics.selection()
        let quoted = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        let prefix = quoted + "\n\n"
        if replyDraft.isEmpty {
            replyDraft = prefix
        } else {
            replyDraft = prefix + replyDraft
        }
        composerFocused = true
    }

    // MARK: - Send reply

    private func sendReply() async {
        isSending = true
        errorMessage = nil
        let trimmed = replyDraft.trimmed
        do {
            try await store.publishReply(content: trimmed, threadID: thread.id, identity: userIdentity)
            Haptics.success()
            replyDraft = ""
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        isSending = false
    }
}

// FeedbackBubble has been extracted to FeedbackBubble.swift.
