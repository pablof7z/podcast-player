import WidgetKit
import SwiftUI

/// Registers all widgets shipped with the app.
@main
struct PodcastrWidgetBundle: WidgetBundle {
    var body: some Widget {
        ItemsWidget()
    }
}
