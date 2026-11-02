import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer of the « Voir tout » grid: a library's items, newest added first. No filters, no sort.
struct RecentGridScreen: View {
    let model: HomeModel
    let library: Library
    let onPlay: (PlayTarget) -> Void
    @State private var hasLoaded = false
    @State private var failure: UserFacingError?

    var body: some View {
        let content = model.grid(for: library)
        RecentGridView(
            title: library.name,
            items: content.items,
            isLoading: !hasLoaded && content.isEmpty,
            failureMessage: content.isEmpty ? failure.map { _ in String(localized: "Impossible de charger la bibliothèque.") } : nil,
            onPlay: { id in
                if let target = content.target(for: id) { onPlay(target) }
            }
        )
        .task {
            failure = await model.refreshGrid(for: library)
            hasLoaded = true
        }
    }
}
