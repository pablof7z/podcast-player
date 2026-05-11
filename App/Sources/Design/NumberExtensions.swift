import Foundation

// MARK: - Progress fraction clamping

extension Double {
    /// Clamp a progress fraction into `0...1` for safe display. Several
    /// download / playback UI surfaces consume fractions that can briefly
    /// fall outside `0...1` (network ETag races, off-by-a-tick reports);
    /// every UI site that displays percentages needs to clamp before
    /// rendering, so the helper lives once here.
    var clamped01: Double { Swift.max(0, Swift.min(1, self)) }
}
