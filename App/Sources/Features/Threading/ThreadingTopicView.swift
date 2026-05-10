import SwiftUI

// MARK: - Threading topic view

/// UX-09 §6.3 timeline detail. Vertical list of every recorded mention of a
/// `ThreadingTopic`, ordered newest-first, each row carrying the host show,
/// episode title, transcript snippet, a tappable timestamp chip, a
/// confidence dot, and an amber seam for contradictions.
///
/// Tap on a timestamp chip dispatches `play_episode_at` via `PlaybackState`
/// (set the episode + seek + play) — same contract the wiki citation chip
/// uses, so the threading and wiki surfaces feel like one fabric.
///
/// A glass capsule footer hands off to the wiki page for the same slug,
/// matching the §3 boundary: threading is *episodic recall*; wiki is
/// *synthesised knowledge*.
struct ThreadingTopicView: View {

    let topicID: UUID

    @Environment(AppStateStore.self) private var store
    @Environment(PlaybackState.self) private var playback
    @State private var service = ThreadingInferenceService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let topic {
                    header(topic)
                    if let definition = topic.definition, !definition.isEmpty {
                        Text(definition)
                            .font(.system(.body, design: .serif))
                            .italic()
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }
                    Divider().overlay(Color.primary.opacity(0.18))
                    timeline
                    wikiHandoff(for: topic)
                } else {
                    missingTopic
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(paperBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task { service.attach(store: store) }
    }

    // MARK: - Sections

    private func header(_ topic: ThreadingTopic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.displayName)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .tracking(-0.4)
                .foregroundStyle(.primary)
            Text(metadataLine(for: topic))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.displayName), \(topic.episodeMentionCount) mentions")
    }

    private var timeline: some View {
        // Read through the service so the spec'd surface
        // (`ThreadingInferenceService.mentions(forTopic:)`) is the live read
        // path — the service is attached on `.task` above so the lookup
        // resolves to the running store rather than the empty fallback.
        let mentions = service.mentions(forTopic: topicID)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Timeline")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            if mentions.isEmpty {
                Text("No mentions recorded yet for this topic.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(mentions) { mention in
                    ThreadingMentionRow(
                        mention: mention,
                        episode: store.episode(id: mention.episodeID),
                        subscriptionTitle: subscriptionTitle(for: mention),
                        onPlay: { play(mention: mention) }
                    )
                }
            }
        }
    }

    private var missingTopic: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("This topic is no longer in your library.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func wikiHandoff(for topic: ThreadingTopic) -> some View {
        Divider().overlay(Color.primary.opacity(0.10))
        Text("Open the wiki entry for \u{201C}\(topic.displayName)\u{201D} \u{2192}")
            .font(.system(.footnote, design: .serif))
            .italic()
            .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.10))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            )
            .accessibilityLabel("Open the wiki entry for \(topic.displayName)")
    }

    // MARK: - Actions

    private func play(mention: ThreadingMention) {
        Haptics.selection()
        guard let episode = store.episode(id: mention.episodeID) else { return }
        let startSeconds = TimeInterval(mention.startMS) / 1_000
        if playback.episode?.id == episode.id {
            playback.seek(to: startSeconds)
        } else {
            playback.setEpisode(episode)
            playback.seek(to: startSeconds)
        }
        playback.play()
    }

    // MARK: - Helpers

    private var topic: ThreadingTopic? {
        store.threadingTopic(id: topicID)
    }

    private func metadataLine(for topic: ThreadingTopic) -> String {
        var parts: [String] = ["\(topic.episodeMentionCount) episodes"]
        if topic.contradictionCount > 0 {
            parts.append("\(topic.contradictionCount) contradiction\(topic.contradictionCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func subscriptionTitle(for mention: ThreadingMention) -> String? {
        guard let episode = store.episode(id: mention.episodeID) else { return nil }
        return store.subscription(id: episode.subscriptionID)?.title
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

