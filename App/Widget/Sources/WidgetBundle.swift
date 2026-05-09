import WidgetKit
import SwiftUI

/// Registers all widgets shipped with the app.
@main
struct PodcastrWidgetBundle: WidgetBundle {
    var body: some Widget {
        PodcastrPlaceholderWidget()
    }
}

/// Placeholder widget shown until the podcast-themed widgets are implemented.
/// A `WidgetBundle` must vend at least one `Widget`, so this keeps the extension
/// installable without surfacing the deprecated todo-list content.
struct PodcastrPlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.f7z.podcast.placeholder", provider: PlaceholderProvider()) { _ in
            ZStack {
                ContainerRelativeShape().fill(Color(.systemBackground))
                Text("Podcastr")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .configurationDisplayName("Podcastr")
        .description("More widgets coming soon.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
