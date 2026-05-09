import SwiftUI

// MARK: - Wiki page view

/// Single-page renderer with the editorial paper feel from UX-04 §4.
///
/// The page itself is **paper, not glass** — solid warm canvas, hairline
/// dividers, single column at ~62 ch on phones. Glass is reserved for
/// floating elements (the citation peek lives in `CitationPeekView`).
struct WikiPageView: View {

    let page: WikiPage

    @State private var peeking: WikiCitation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summary
                ForEach(page.sections.sorted(by: { $0.ordinal < $1.ordinal })) { section in
                    sectionView(section)
                }
                citationsList
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(paperBackground)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $peeking) { citation in
            CitationPeekView(citation: citation)
                .presentationDetents([.fraction(0.42), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .tracking(-0.4)
                .foregroundStyle(.primary)
            Text(metadataLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title), \(page.kind.displayName)")
    }

    private var summary: some View {
        Text(page.summary)
            .font(.system(.body, design: .serif))
            .italic()
            .foregroundStyle(.primary)
            .lineSpacing(4)
    }

    private func sectionView(_ section: WikiSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
                .overlay(Color.primary.opacity(0.18))
            Text(section.heading)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            if let note = section.editorialNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
            ForEach(section.claims) { claim in
                claimView(claim)
            }
        }
    }

    private func claimView(_ claim: WikiClaim) -> some View {
        HStack(alignment: .top, spacing: 12) {
            confidenceMargin(for: claim.confidence)
            VStack(alignment: .leading, spacing: 8) {
                Text(claim.text)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
                if !claim.citations.isEmpty {
                    citationChips(for: claim)
                }
                if claim.isContestedByUser {
                    Label("You flagged this", systemImage: "exclamationmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.10))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(claim.text)
        .accessibilityValue(claim.confidence.accessibilityValue)
    }

    private func confidenceMargin(for band: WikiConfidenceBand) -> some View {
        Rectangle()
            .fill(color(for: band))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    private func citationChips(for claim: WikiClaim) -> some View {
        FlexibleChipRow(items: claim.citations) { citation in
            Button {
                peeking = citation
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text(citation.formattedTimestamp)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color(red: 0.72, green: 0.45, blue: 0.10).opacity(0.14))
                )
                .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Citation at \(citation.formattedTimestamp), plays clip")
        }
    }

    @ViewBuilder
    private var citationsList: some View {
        if !page.citations.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Divider().overlay(Color.primary.opacity(0.18))
                Text("Citations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                ForEach(page.citations) { citation in
                    Button {
                        peeking = citation
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(citation.formattedTimestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.10))
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                if let speaker = citation.speaker {
                                    Text(speaker)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                                Text("\u{201C}\(citation.quoteSnippet)\u{201D}")
                                    .font(.system(.footnote, design: .serif))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.primary.opacity(0.10))
            HStack {
                Text("rev \(page.compileRevision) · \(page.model)")
                Spacer()
                Text(page.generatedAt, format: .relative(presentation: .named))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var metadataLine: String {
        let count = page.allClaims.flatMap(\.citations).count
        return "\(page.kind.displayName) · \(count) citations · confidence \(Int(page.confidence * 100))%"
    }

    private func color(for band: WikiConfidenceBand) -> Color {
        switch band {
        case .high: Color(red: 0.18, green: 0.55, blue: 0.34)
        case .medium: Color(red: 0.78, green: 0.55, blue: 0.10)
        case .low: Color(red: 0.78, green: 0.18, blue: 0.30)
        }
    }

    private var paperBackground: some View {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.059, blue: 0.071, alpha: 1)
                : UIColor(red: 0.965, green: 0.949, blue: 0.914, alpha: 1)
        })
        .ignoresSafeArea()
    }
}

// MARK: - Flexible chip row

/// Wraps citation chips when they exceed the available width. Keeps the
/// editorial layout clean even on narrow phones.
private struct FlexibleChipRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // SwiftUI does not ship a built-in flow layout pre-iOS 16, but
        // we target iOS 26, so `Layout` would also work. For simplicity
        // we rely on `LazyVGrid` with adaptive columns.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 84), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}
