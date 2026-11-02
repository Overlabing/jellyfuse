import Foundation
import HomePresentation
import LibraryKit
import Observation

/// Home screen state: the store's shelves, revalidated on appear.
@MainActor
@Observable
final class HomeModel {
    /// Shared with the playback services: a stop patches this store.
    let store: LibraryStore
    private let client: JellyfinClient
    let reachability: ServerReachability
    private(set) var hasLoaded = false
    private(set) var failure: UserFacingError?
    private var isUpdatingList = false

    init(session: Session, client: JellyfinClient) {
        self.client = client
        let probe = Self.makeProbe(client)
        let reachability = ServerReachability(probe: probe)
        self.reachability = reachability
        let storage = (try? FileSnapshotStorage.inCaches())
            ?? FileSnapshotStorage(root: FileManager.default.temporaryDirectory.appending(path: "jellyfuse"))
        store = LibraryStore(owner: session.libraryOwner, api: client, storage: storage, reachability: reachability)
    }

    /// Display content, recomputed from the store (observed): a patch anywhere repaints the shelves.
    var content: HomeContent {
        let client = client
        return HomeMapper.content(
            continueWatching: store.entries(.continueWatching),
            nextUp: store.entries(.nextUp),
            libraries: store.libraries.map {
                LibraryShelfSource(library: $0, entries: store.entries(.latestIn(libraryId: $0.id)))
            },
            isInList: { [store] in store.userData[$0]?.isFavorite ?? false },
            imageURL: Self.makeImageURL(client)
        )
    }

    /// « Ma liste » on the billboard: optimistic through the store; a refusal rolls the button back.
    func toggleBillboardList() async {
        guard let billboard = content.billboard, !isUpdatingList else { return }
        isUpdatingList = true
        defer { isUpdatingList = false }
        let id = billboard.listId
        try? await store.setFavorite(!(store.userData[id]?.isFavorite ?? false), for: id)
    }

    /// The « Voir tout » grid of a library, from the store.
    func grid(for library: Library) -> LibraryGridContent {
        HomeMapper.grid(
            library: library,
            entries: store.entries(.recentGrid(libraryId: library.id)),
            imageURL: Self.makeImageURL(client)
        )
    }

    /// Cold start: nothing cached and the first load has not answered yet.
    var isLoadingCold: Bool { !hasLoaded && content.isEmpty }

    /// The state of one detail screen, backed by this session's store.
    func detailModel(for id: String) -> DetailModel {
        DetailModel(id: id, store: store, client: client)
    }

    /// Revalidates every shelf that is stale; fresh ones are left alone. The library list comes first:
    /// it decides which per-library shelves exist.
    func refresh() async {
        async let resume = load(.continueWatching)
        async let next = load(.nextUp)
        async let libraries = loadLibraries()
        var errors = await [resume, next, libraries].compactMap { $0 }
        errors += await loadLibraryShelves()
        await loadBillboardList()
        hasLoaded = true
        failure = errors.first.map(UserFacingError.init)
    }

    /// Revalidates the « Voir tout » grid of one library.
    func refreshGrid(for library: Library) async -> UserFacingError? {
        await load(.recentGrid(libraryId: library.id)).map(UserFacingError.init)
    }

    /// The billboard of an episode acts on its series, whose favorite flag no shelf carries: the detail
    /// load brings it. Best effort; without it the button reads « Ma liste ».
    private func loadBillboardList() async {
        guard let billboard = content.billboard, billboard.listId != billboard.target.id else { return }
        try? await store.ensureDetailFresh(billboard.listId)
    }

    private func loadLibraryShelves() async -> [any Error] {
        let keys = store.libraries.map { ShelfKey.latestIn(libraryId: $0.id) }
        return await withTaskGroup(of: (any Error)?.self) { group in
            for key in keys { group.addTask { await self.load(key) } }
            var errors: [any Error] = []
            for await error in group { if let error { errors.append(error) } }
            return errors
        }
    }

    private func loadLibraries() async -> (any Error)? {
        do {
            try await store.ensureLibrariesFresh()
            return nil
        } catch {
            return error
        }
    }

    private func load(_ key: ShelfKey) async -> (any Error)? {
        do {
            try await store.ensureFresh(key)
            return nil
        } catch {
            return error
        }
    }

    private nonisolated static func makeProbe(_ client: JellyfinClient) -> @Sendable () async -> Bool {
        { @Sendable in await client.ping() }
    }

    private nonisolated static func makeImageURL(_ client: JellyfinClient) -> HomeMapper.ImageURL {
        { @Sendable id, tag, width in client.imageURL(itemId: id, tag: tag, maxWidth: width) }
    }
}
