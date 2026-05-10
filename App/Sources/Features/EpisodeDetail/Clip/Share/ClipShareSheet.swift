import SwiftUI

// MARK: - ClipShareSheet
//
// Modal surface presented after the composer commits a `Clip`. Hosts:
//   - A live preview of the image card (re-renders when the user toggles
//     subtitle style).
//   - Three primary share actions: image (PNG), video (MP4), link (URL).
//   - Segmented controls for subtitle style + video aspect ratio.
//
// Each action produces a temp file via `ClipExporter`, then hands the URL
// to a `ShareLink`. We use `ShareLink` (not `UIActivityViewController`) for
// file-URL items per the bug history note in `ShareSheet.swift`.
struct ClipShareSheet: View {
    let clip: Clip
    let episode: Episode
    let subscription: PodcastSubscription

    @State private var style: ClipExporter.SubtitleStyle = .editorial
    @State private var aspect: ClipVideo.Aspect = .square

    @State private var imageURL: URL?
    @State private var isRenderingImage = false
    @State private var lastError: String?

    private var deepLink: URL { ClipExporter.shared.deepLink(clip) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    preview
                    styleSection
                    aspectSection
                    actionGrid
                    if let lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .navigationTitle("Share clip")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ClipImageCardView(
            showName: subscription.title,
            episodeTitle: episode.title,
            artwork: nil,  // Live preview skips network fetch — exporter loads.
            pullQuote: clip.transcriptText,
            speakerName: clip.speakerID,
            timestamp: ClipExporter.formatTimestamp(seconds: clip.startSeconds),
            deepLink: deepLink.absoluteString,
            style: style
        )
        .scaleEffect(0.3)
        .frame(width: 1080 * 0.3, height: 1080 * 0.3)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Corner.lg, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 8)
    }

    // MARK: - Controls

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Subtitle style")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Subtitle style", selection: $style) {
                ForEach(ClipExporter.SubtitleStyle.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aspectSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Video aspect ratio")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Aspect", selection: $aspect) {
                ForEach(ClipVideo.Aspect.allCases, id: \.self) { a in
                    Text(a.displayName).tag(a)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Actions

    private var actionGrid: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            imageAction
            videoAction
            linkAction
        }
    }

    private var imageAction: some View {
        Group {
            if let imageURL {
                ShareLink(item: imageURL) {
                    actionRow(systemImage: "photo", title: "Share image",
                              subtitle: "1080×1080 PNG", trailing: "Ready")
                }
            } else {
                Button {
                    Task { await renderImage() }
                } label: {
                    actionRow(systemImage: "photo", title: "Render image",
                              subtitle: "1080×1080 PNG",
                              trailing: isRenderingImage ? "…" : "Tap")
                }
                .disabled(isRenderingImage)
            }
        }
        .onChange(of: style) { _, _ in
            // Style changes invalidate the rendered file.
            imageURL = nil
        }
    }

    private var videoAction: some View {
        // Video export is intentionally stubbed in this build (see
        // `ClipVideoComposer` header for the punt details). Surface as
        // disabled "Coming soon" rather than letting taps surface a raw
        // `notImplemented` error in the user's face.
        actionRow(
            systemImage: "waveform",
            title: "Share video",
            subtitle: "MP4 with subtitles",
            trailing: "Soon"
        )
        .opacity(0.55)
    }

    private var linkAction: some View {
        ShareLink(item: deepLink) {
            actionRow(
                systemImage: "link",
                title: "Share link",
                subtitle: deepLink.absoluteString,
                trailing: "Ready"
            )
        }
    }

    @ViewBuilder
    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        trailing: String
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Corner.md, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
    }

    // MARK: - Render orchestration

    private func renderImage() async {
        isRenderingImage = true
        lastError = nil
        defer { isRenderingImage = false }
        do {
            let url = try await ClipExporter.shared.exportImage(
                clip,
                episode: episode,
                subscription: subscription,
                theme: style
            )
            imageURL = url
        } catch {
            lastError = "Couldn't render image: \(error.localizedDescription)"
        }
    }

    // Video render orchestration intentionally omitted — see
    // `ClipVideoComposer` header for the punt details. The button is
    // disabled in `videoAction` so this code path isn't exercised.
}

// MARK: - Preview

#Preview {
    ClipShareSheet(
        clip: Clip(
            episodeID: UUID(),
            subscriptionID: UUID(),
            startMs: 14 * 60_000 + 31_000,
            endMs: 14 * 60_000 + 58_000,
            transcriptText: "Metabolic flexibility isn't a diet — it's a property of the mitochondria."
        ),
        episode: Episode(
            subscriptionID: UUID(),
            guid: "preview",
            title: "How to Think About Keto",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/x.mp3")!
        ),
        subscription: PodcastSubscription(
            feedURL: URL(string: "https://example.com/feed")!,
            title: "The Tim Ferriss Show"
        )
    )
}
