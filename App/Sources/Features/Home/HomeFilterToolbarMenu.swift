import SwiftUI

// MARK: - HomeFilterToolbarMenu

/// Top-trailing toolbar menu for Home. Houses the LibraryFilter Picker,
/// the user-defined PodcastCategory Picker, and the list/grid layout
/// toggle. Persistence is owned by the parent `HomeView` via `@AppStorage`
/// — this view only renders the choices and forwards selections via
/// bindings.
struct HomeFilterToolbarMenu: View {
    @Binding var filter: LibraryFilter
    @Binding var categoryID: String
    @Binding var layout: HomeSubscriptionLayout
    let categories: [PodcastCategory]

    var body: some View {
        Menu {
            Picker("Status", selection: $filter) {
                ForEach(LibraryFilter.allCases) { f in
                    Label(f.label, systemImage: f.systemImage ?? "circle")
                        .tag(f)
                }
            }

            if !categories.isEmpty {
                Picker("Category", selection: $categoryID) {
                    Text("All categories").tag("")
                    ForEach(categories) { c in
                        Text(c.name).tag(c.id.uuidString)
                    }
                }
            }

            Divider()

            Picker("Layout", selection: $layout) {
                ForEach(HomeSubscriptionLayout.allCases) { l in
                    Label(l.label, systemImage: l.symbol).tag(l)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
        .accessibilityLabel("Filter and layout")
    }
}
