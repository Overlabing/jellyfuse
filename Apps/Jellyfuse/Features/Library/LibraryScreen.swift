import DesignSystem
import HomePresentation
import LibraryKit
import SwiftUI

/// Where a Films / Séries tab's own stack can go.
enum LibraryRoute: Hashable {
    case detail(String)
    case collection(id: String, name: String)
    case person(id: String, name: String)
}

/// Composition layer of the Films / Séries tabs: the paginated grid of every movie (or series), with
/// sort, filters and alphabet jump; a poster opens its detail screen, a collection card its own list.
struct LibraryScreen: View {
    let home: HomeModel
    let kind: Library.Kind
    let onPlay: (PlayTarget) -> Void
    @State private var tab: LibraryTabModel
    @State private var path: [LibraryRoute] = []
    @State private var isPanelOpen = false

    init(home: HomeModel, kind: Library.Kind, onPlay: @escaping (PlayTarget) -> Void) {
        self.home = home
        self.kind = kind
        self.onPlay = onPlay
        _tab = State(initialValue: home.libraryTabModel(kind: kind))
    }

    private var title: String { kind == .tvshows ? String(localized: "Séries") : String(localized: "Films") }

    var body: some View {
        NavigationStack(path: $path) {
            let key = tab.key
            LibraryView(
                title: title,
                summary: tab.summary,
                content: tab.grid.content(for: key),
                collections: tab.showsCollections ? collectionPosters : [],
                isLoading: tab.grid.isLoading(key),
                failureMessage: tab.grid.failure(for: key).map { _ in String(localized: "Impossible de charger la bibliothèque.") },
                emptyMessage: key.filter.isActive ? String(localized: "Aucun résultat avec ces filtres.") : String(localized: "Rien à afficher pour l'instant."),
                isLoadingMore: tab.grid.isLoadingMore,
                loadMoreFailed: tab.grid.loadMoreFailed,
                scrollResetToken: key,
                onOpenFilters: { isPanelOpen = true },
                onOpen: open,
                onLoadMore: { Task { await tab.grid.loadMore(key) } }
            )
            .hidesNavigationBar()
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .detail(let id):
                    DetailScreen(
                        model: home.detailModel(for: id), onPlay: onPlay,
                        onOpenPerson: { path.append(.person(id: $0, name: $1)) }
                    )
                    .transparentNavigationBar()
                case .collection(let id, let name):
                    FixedGridScreen(
                        title: name, key: GridKey(.collection(id: id), sort: LibrarySort(.year, .ascending)),
                        model: home.gridModel(), onOpen: open
                    )
                case .person(let id, let name):
                    FixedGridScreen(
                        title: name, key: GridKey(.person(id: id), sort: LibrarySort(.year)),
                        model: home.gridModel(), onOpen: open
                    )
                }
            }
        }
        .task { await tab.loadLibraries() }
        .task(id: tab.key) { await tab.grid.refresh(tab.key) }
        .task(id: tab.collectionsKey) {
            if let key = tab.collectionsKey { await tab.grid.refresh(key) }
        }
        .sheet(isPresented: $isPanelOpen) {
            FilterSortPanel(
                sort: tab.sort, filter: tab.filter, startsAt: tab.startsAt,
                onSelectField: { tab.select($0) }, onSelectDirection: { tab.select($0) },
                onSetUnwatched: { tab.setUnwatchedOnly($0) }, onSetFavorites: { tab.setFavoritesOnly($0) },
                onJump: { tab.jump(toLetter: $0) }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationBackground(Design.Palette.canvas)
            #endif
        }
    }

    private var collectionPosters: [PosterModel] {
        tab.collectionsKey.map { tab.grid.content(for: $0).items } ?? []
    }

    /// A collection opens its list, everything else its detail screen.
    private func open(_ id: String) {
        if let collection = home.store.items[id], collection.kind == .boxSet {
            path.append(.collection(id: id, name: collection.name))
        } else {
            path.append(.detail(id))
        }
    }
}
