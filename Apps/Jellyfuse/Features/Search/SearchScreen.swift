import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer of the Recherche tab: the system `.searchable` field drives `SearchModel`; a card
/// pushes the detail screen on the tab's own stack (Menu pops it).
struct SearchScreen: View {
    let home: HomeModel
    let onPlay: (PlayTarget) -> Void
    @State private var path: [String] = []

    var body: some View {
        @Bindable var model = home.search
        NavigationStack(path: $path) {
            SearchView(
                phase: model.phase,
                content: model.content,
                recents: home.content.libraryShelves,
                onOpenDetail: { path.append($0) },
                onRetry: { model.retry() }
            )
            .navigationDestination(for: String.self) { id in
                DetailScreen(model: home.detailModel(for: id), onPlay: onPlay)
            }
        }
        .searchable(text: $model.query, prompt: String(localized: "Films, séries, épisodes"))
    }
}
