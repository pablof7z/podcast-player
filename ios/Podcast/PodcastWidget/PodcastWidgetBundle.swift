import SwiftUI
import WidgetKit

/// Registers every widget shipped in the `PodcastWidget` extension.
///
/// Today this is the lone `PodcastLiveActivityWidget` (lock screen +
/// Dynamic Island). Home-screen widgets that read the `WidgetSnapshot`
/// JSON `PlatformCapability` writes to the App Group will land here in
/// a follow-up milestone — drop them into the `body` builder.
@main
struct PodcastWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            PodcastLiveActivityWidget()
        }
    }
}
