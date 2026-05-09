import SwiftUI
import UIKit

// MARK: - ShareSheet

/// UIKit wrapper that presents a system share sheet via UIActivityViewController.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ShareButton

/// A button that presents a share sheet when tapped.
///
/// Example usage:
/// ```swift
/// ShareButton(items: [item.title, "Shared from Podcastr"]) {
///     Image(systemName: "square.and.arrow.up")
/// }
/// ```
struct ShareButton<Label: View>: View {
    let items: [Any]
    let label: () -> Label

    @State private var isPresented = false

    init(items: [Any], @ViewBuilder label: @escaping () -> Label) {
        self.items = items
        self.label = label
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            ShareSheet(items: items)
        }
    }
}
