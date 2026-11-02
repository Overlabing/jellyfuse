import HomePresentation
import LibraryKit
import Observation

/// Detail screen state for one movie or series: reads the store (observed), revalidates on appear,
/// and toggles « Ma liste » / « Vu » through the store's optimistic mutations.
@MainActor
@Observable
final class DetailModel {
    let id: String
    private let store: LibraryStore
    private let client: JellyfinClient
    /// The season chip chosen by the user; nil follows the play target's season.
    var selectedSeasonId: String?
    private(set) var hasLoaded = false
    private(set) var failure: UserFacingError?
    /// The last user action the server refused (its optimistic change was rolled back).
    private(set) var actionFailure: ActionFailure?
    private var isUpdatingFavorite = false
    private var watchedUpdating = Set<String>()

    enum ActionFailure {
        case favorite
        case watched
    }

    init(id: String, store: LibraryStore, client: JellyfinClient) {
        self.id = id
        self.store = store
        self.client = client
    }

    /// Nil until the item is known to the store (it always is when reached from a shelf).
    var content: DetailContent? {
        guard let item = store.items[id] else { return nil }
        let client = client
        return DetailMapper.content(
            item: item,
            detail: store.detail(id),
            userData: store.userData[id] ?? .none,
            seasons: store.seasons(of: id),
            episodes: store.episodes(of: id),
            selectedSeasonId: selectedSeasonId,
            imageURL: { @Sendable id, kind, tag, width in client.imageURL(itemId: id, kind: kind, tag: tag, maxWidth: width) }
        )
    }

    /// Children of a series are still loading.
    var isLoadingChildren: Bool { !hasLoaded && failure == nil }

    func refresh() async {
        // The item may be unknown here (a shelf episode opening its series): only the detail answer
        // says whether children exist, so an unknown kind checks again once the detail has landed.
        let knownSeries = store.items[id]?.kind == .series
        async let detail = attempt { try await self.store.ensureDetailFresh(self.id) }
        async let children = attempt { if knownSeries { try await self.store.ensureSeriesFresh(self.id) } }
        var errors = await [detail, children].compactMap { $0 }
        if !knownSeries, store.items[id]?.kind == .series,
           let error = await attempt({ try await self.store.ensureSeriesFresh(self.id) }) {
            errors.append(error)
        }
        hasLoaded = true
        failure = errors.first.map(UserFacingError.init)
    }

    func toggleFavorite() async {
        guard !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }
        do {
            try await store.setFavorite(!(store.userData[id]?.isFavorite ?? false), for: id)
            actionFailure = nil
        } catch {
            actionFailure = .favorite
        }
    }

    /// Marks a movie or an episode (of this series) watched or not; one request per item at a time.
    func setWatched(_ watched: Bool, for itemId: String) async {
        guard watchedUpdating.insert(itemId).inserted else { return }
        defer { watchedUpdating.remove(itemId) }
        do {
            try await store.setPlayed(watched, for: itemId)
            actionFailure = nil
        } catch {
            actionFailure = .watched
        }
    }

    func toggleWatched() async {
        await setWatched(!(store.userData[id]?.played ?? false), for: id)
    }

    private func attempt(_ body: () async throws -> Void) async -> (any Error)? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }
}
