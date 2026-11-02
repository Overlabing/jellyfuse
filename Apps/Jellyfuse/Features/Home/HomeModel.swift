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
            recentlyAdded: store.entries(.recentlyAdded),
            imageURL: Self.makeImageURL(client)
        )
    }

    /// Cold start: nothing cached and the first load has not answered yet.
    var isLoadingCold: Bool { !hasLoaded && content.isEmpty }

    func streamURL(for target: PlayTarget) -> URL? {
        client.streamURL(itemId: target.id, mediaSourceId: target.id)
    }

    /// Revalidates every shelf that is stale; fresh ones are left alone.
    func refresh() async {
        async let resume = load(.continueWatching)
        async let next = load(.nextUp)
        async let recent = load(.recentlyAdded)
        let errors = await [resume, next, recent].compactMap { $0 }
        hasLoaded = true
        failure = errors.first.map(UserFacingError.init)
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
