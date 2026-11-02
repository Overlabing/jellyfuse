import HomePresentation
import LibraryKit
import SwiftUI

/// Where the Recherche tab's stack can go (same shape as HomeRoute).
private enum SearchRoute: Hashable {
    case detail(String)
    case person(id: String, name: String)
}

/// Composition layer of the Recherche tab: the system `.searchable` field drives `SearchModel`; a card
/// pushes the detail screen on the tab's own stack (Menu pops it).
struct SearchScreen: View {
    let home: HomeModel
    let onPlay: (PlayTarget) -> Void
    @State private var path: [SearchRoute] = []

    var body: some View {
        @Bindable var model = home.search
        NavigationStack(path: $path) {
            SearchView(
                phase: model.phase,
                content: model.content,
                recents: home.content.libraryShelves,
                onOpenDetail: { path.append(.detail($0)) },
                onRetry: { model.retry() }
            )
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case .detail(let id):
                    DetailScreen(
                        model: home.detailModel(for: id), onPlay: onPlay,
                        onOpenPerson: { path.append(.person(id: $0, name: $1)) }
                    )
                case .person(let id, let name):
                    FixedGridScreen(
                        title: name, key: GridKey(.person(id: id), sort: LibrarySort(.year)),
                        model: home.gridModel(), onOpen: { path.append(.detail($0)) }
                    )
                }
            }
        }
        .searchable(text: $model.query, prompt: String(localized: "Films, séries, épisodes"))
    }
}
