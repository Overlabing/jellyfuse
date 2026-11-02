import DesignSystem
import Foundation
import HomePresentation
import LibraryKit
import PlaybackEngine
import PlayerPresentation

/// The episode that follows the one playing: what to play and how the card presents it.
struct NextEpisode: Equatable {
    /// Always from the beginning: the viewer is not asked « Reprendre / Recommencer ».
    let target: PlayTarget
    /// `S1E5 · Titre`.
    let title: String
    let thumbnail: ArtworkSource
}

/// What a playback needs from the session: the resolver (PlaybackInfo -> source) and the reporter (journal,
/// Start/Progress/Stopped). One instance per session, so the journal is drained once at sign-in and again each
/// time the server becomes reachable, whether or not a player is open.
@MainActor
final class PlaybackServices {
    let reporter: PlaybackReporter
    /// The viewer's remembered audio / subtitle languages, per movie or series.
    let trackPreferences: TrackPreferenceStore
    private let resolver: PlaybackResolver
    private let thresholds: ResumeThresholdsCache
    private let userId: String
    private let store: LibraryStore
    private let client: JellyfinClient
    private let extras: any PlayerExtrasAPI

    init(session: Session, client: JellyfinClient, store: LibraryStore, reachability: ServerReachability) {
        userId = session.userId
        trackPreferences = TrackPreferenceStore(owner: session.libraryOwner)
        self.store = store
        self.client = client
        extras = client
        resolver = PlaybackResolver(api: client, profile: .jellyfuse())
        let thresholds = ResumeThresholdsCache(fetch: Self.makeThresholdsFetch(client))
        self.thresholds = thresholds
        reporter = PlaybackReporter(
            api: client, storage: UserDefaultsJournalStorage(), owner: session.libraryOwner,
            connectivity: ReachabilityConnectivity(reachability),
            effects: LibraryStoreEffects(store: store, thresholds: Self.makeThresholdsRead(thresholds))
        )
        let reporter = reporter
        reachability.onChange = { [weak reachability] _ in
            guard reachability?.isOnline == true else { return }
            Task { await reporter.drain() }
        }
        // Reports a previous run could not send (offline, killed): retried at launch.
        Task { await reporter.drain() }
    }

    /// The item as the library knows it, for the title shown over the video. Nil when it was never listed.
    func item(_ id: String) -> MediaItem? { store.items[id] }

    /// `PlaybackInfo` for the item, from the resume position. Never cached.
    func resolve(itemId: String, startPositionTicks: Int64) async throws -> ResolvedPlayback {
        // Read now, while online, so the local patch at stop does not depend on the network.
        Task { [thresholds] in _ = await thresholds.value() }
        let scope = trackScope(itemId)
        return try await resolver.resolve(PlaybackRequest(
            itemId: itemId, userId: userId, startPositionTicks: startPositionTicks,
            tracks: trackPreferences.input(scope: scope)
        ))
    }

    /// Remembered track choices belong to the movie or to the whole series.
    func trackScope(_ itemId: String) -> String {
        TrackPreferenceStore.scope(itemId: itemId, seriesId: store.items[itemId]?.seriesId)
    }

    /// The item's detail (synopsis, chapters), from the library or fetched. Nil offline when never loaded.
    func detail(_ id: String) async -> ItemDetail? {
        try? await store.ensureDetailFresh(id)
        return store.detail(id)
    }

    /// The intro and credits of the item. None when the server has none or predates them (10.10).
    func segments(_ id: String) async -> ItemSegments {
        (try? await extras.segments(itemId: id)) ?? .none
    }

    /// The scrub thumbnails of the media source resolved for this playback. Nil when there are none or offline.
    func trickplay(itemId: String, mediaSourceId: String) async -> TrickplaySheet? {
        try? await extras.trickplay(itemId: itemId, mediaSourceId: mediaSourceId)
    }

    /// The tile image `index` of the item's trickplay at `width`.
    func trickplayTileURL(itemId: String, width: Int, index: Int) -> URL? {
        extras.trickplayTileURL(itemId: itemId, width: width, index: index)
    }

    /// The episode after `id` in its series, once the series' episodes are loaded. Nil for a film, the last
    /// episode, or when the series cannot be loaded (offline, never listed).
    func nextEpisode(after id: String) async -> NextEpisode? {
        guard let current = store.items[id], current.kind == .episode, let seriesId = current.seriesId else { return nil }
        try? await store.ensureSeriesFresh(seriesId)
        guard let next = UpNext.next(after: id, in: store.episodes(of: seriesId)) else { return nil }
        let title = UpNext.title(of: next)
        return NextEpisode(
            target: PlayTarget(id: next.id, title: next.seriesName ?? next.name, resumeSeconds: 0),
            title: title,
            thumbnail: ArtworkSource(
                url: client.imageURL(itemId: next.id, kind: .primary, tag: next.primaryImageTag, maxWidth: 512),
                placeholderTitle: next.name
            )
        )
    }

    private nonisolated static func makeThresholdsFetch(_ client: JellyfinClient) -> @Sendable () async throws -> ResumeThresholds? {
        { @Sendable in try await client.resumeThresholds() }
    }

    private nonisolated static func makeThresholdsRead(_ cache: ResumeThresholdsCache) -> @Sendable () async -> ResumeThresholds? {
        { @Sendable in await cache.value() }
    }
}
