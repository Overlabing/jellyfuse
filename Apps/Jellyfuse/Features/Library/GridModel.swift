import HomePresentation
import LibraryKit
import Observation

/// State of paginated poster grids over the store: first-page revalidation, load-more, and what each
/// key has answered. Stateless about *which* grid is shown (the caller passes the `GridKey`), so one
/// model serves the library tab (key follows sort and filters), a collection or a person.
@MainActor
@Observable
final class GridModel {
    private let store: LibraryStore
    private let client: JellyfinClient
    private var settled = Set<GridKey>()
    private var failures: [GridKey: UserFacingError] = [:]
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false

    init(store: LibraryStore, client: JellyfinClient) {
        self.store = store
        self.client = client
    }

    /// What has loaded so far, mapped for display (user data included, so « vu » and favorites follow).
    func content(for key: GridKey) -> PosterGridContent {
        LibraryGridMapper.content(
            entries: store.gridEntries(key),
            total: store.gridTotal(key),
            isComplete: store.isGridComplete(key),
            imageURL: HomeModel.makeImageURL(client)
        )
    }

    /// The first page has not answered yet (neither with items nor with an error).
    func isLoading(_ key: GridKey) -> Bool { !settled.contains(key) }

    func failure(for key: GridKey) -> UserFacingError? { failures[key] }

    /// Revalidates the first page unless fresh.
    func refresh(_ key: GridKey) async {
        do {
            try await store.ensureGridFresh(key)
            failures[key] = nil
        } catch {
            failures[key] = UserFacingError(error)
        }
        settled.insert(key)
    }

    /// Appends the next page. One at a time; a failure keeps what is loaded and offers a retry.
    func loadMore(_ key: GridKey) async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            try await store.loadNextGridPage(key)
        } catch {
            loadMoreFailed = true
        }
    }
}

/// The Films / Séries tab: the sort, filters and alphabet jump the user picked, and the key they make.
@MainActor
@Observable
final class LibraryTabModel {
    let kind: Library.Kind
    let grid: GridModel
    private let store: LibraryStore
    private(set) var sort = LibrarySort.default
    private(set) var filter = LibraryFilter.none
    private(set) var startsAt: String?

    init(kind: Library.Kind, store: LibraryStore, grid: GridModel) {
        self.kind = kind
        self.store = store
        self.grid = grid
    }

    var key: GridKey { GridKey(.library(kind), sort: sort, filter: filter, startsAt: startsAt) }

    /// The collections row (Films only), once the collections library is known.
    var collectionsKey: GridKey? {
        guard kind == .movies, let library = store.libraries(of: .boxsets).first else { return nil }
        return GridKey(.collections(libraryId: library.id))
    }

    /// The row only shows on the plain list: a filter or a jump asks for a narrower view.
    var showsCollections: Bool { collectionsKey != nil && !filter.isActive && startsAt == nil }

    var summary: String { LibraryGridMapper.summary(sort: sort, filter: filter, startsAt: startsAt) }

    func select(_ field: LibrarySortField) {
        guard field != sort.field else { return }
        sort = LibrarySort(field)
        resetJumpIfUnsupported()
    }

    func select(_ direction: SortDirection) {
        sort.direction = direction
        resetJumpIfUnsupported()
    }

    func setUnwatchedOnly(_ value: Bool) { filter.unwatchedOnly = value }
    func setFavoritesOnly(_ value: Bool) { filter.favoritesOnly = value }

    func jump(toLetter letter: String) { startsAt = LibraryGridMapper.startsAt(forLetter: letter) }

    /// The libraries list decides whether the collections row exists: load it if the home has not.
    func loadLibraries() async {
        try? await store.ensureLibrariesFresh()
    }

    private func resetJumpIfUnsupported() {
        if !sort.supportsLetterJump { startsAt = nil }
    }
}
