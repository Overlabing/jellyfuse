import Foundation
import HomePresentation
import LibraryKit
import Observation

/// Home screen state: the store's shelves, revalidated on appear.
@MainActor
@Observable
final class HomeModel {
    private let store: LibraryStore
    private let client: JellyfinClient
    private let reachability: ServerReachability
    private(set) var hasLoaded = false
    private(set) var failure: UserFacingError?

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
            imageURL: Self.makeImageURL(client)
        )
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

    func streamURL(for target: PlayTarget) -> URL? {
        client.streamURL(itemId: target.id, mediaSourceId: target.id)
    }

    /// Revalidates every shelf that is stale; fresh ones are left alone. The library list comes first:
    /// it decides which per-library shelves exist.
    func refresh() async {
        async let resume = load(.continueWatching)
        async let next = load(.nextUp)
        async let libraries = loadLibraries()
        var errors = await [resume, next, libraries].compactMap { $0 }
        errors += await loadLibraryShelves()
        hasLoaded = true
        failure = errors.first.map(UserFacingError.init)
    }

    /// Revalidates the « Voir tout » grid of one library.
    func refreshGrid(for library: Library) async -> UserFacingError? {
        await load(.recentGrid(libraryId: library.id)).map(UserFacingError.init)
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
