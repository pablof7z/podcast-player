import SwiftUI

// MARK: - FeedbackBubble

struct FeedbackBubble: View {
    let content: String
    let isFromMe: Bool
    let createdAt: Date
    var onQuoteReply: (() -> Void)? = nil

    private enum Layout {
        static let spacerMinLength: CGFloat = 60
        static let bubbleCornerRadius: CGFloat = 18
        /// Horizontal inset inside each bubble.
        static let bubblePaddingH: CGFloat = 12
        /// Vertical padding between adjacent bubble rows.
        static let rowPaddingV: CGFloat = 2
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isFromMe { Spacer(minLength: Layout.spacerMinLength) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: AppTheme.Spacing.xs) {
                if isFromMe {
                    myBubble
                } else {
                    theirBubble
                }

                Text(createdAt, style: .time)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isFromMe { Spacer(minLength: Layout.spacerMinLength) }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, Layout.rowPaddingV)
    }

    private var myBubble: some View {
        Text(content)
            .padding(.horizontal, Layout.bubblePaddingH)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: Layout.bubbleCornerRadius))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .copyableTextMenu(content)
    }

    private var theirBubble: some View {
        Text(content)
            .padding(.horizontal, Layout.bubblePaddingH)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Layout.bubbleCornerRadius))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = content
                    Haptics.selection()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let onQuoteReply {
                    Button {
                        onQuoteReply()
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                }
            }
    }
}
