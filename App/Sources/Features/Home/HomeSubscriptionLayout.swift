import Foundation

/// Persisted layout choice for the merged Home subscription surface.
///
/// `@AppStorage("home.subscriptionLayout")` reads the rawValue. Default is
/// `.list` — denser surface, recency-sorted, matches the brief.
enum HomeSubscriptionLayout: String, CaseIterable, Identifiable, Sendable {
    case list
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}
