import Foundation
import LibraryKit
import PlaybackEngine

/// What a playback needs from the session: the resolver (PlaybackInfo -> source) and the reporter (journal,
/// Start/Progress/Stopped). One instance per session, so the journal is drained once at sign-in and again each
/// time the server becomes reachable, whether or not a player is open.
@MainActor
final class PlaybackServices {
    let reporter: PlaybackReporter
    private let resolver: PlaybackResolver
    private let thresholds: ResumeThresholdsCache
    private let userId: String
    private let store: LibraryStore

    init(session: Session, client: JellyfinClient, store: LibraryStore, reachability: ServerReachability) {
        userId = session.userId
        self.store = store
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
        return try await resolver.resolve(PlaybackRequest(itemId: itemId, userId: userId, startPositionTicks: startPositionTicks))
    }

    private nonisolated static func makeThresholdsFetch(_ client: JellyfinClient) -> @Sendable () async throws -> ResumeThresholds? {
        { @Sendable in try await client.resumeThresholds() }
    }

    private nonisolated static func makeThresholdsRead(_ cache: ResumeThresholdsCache) -> @Sendable () async -> ResumeThresholds? {
        { @Sendable in await cache.value() }
    }
}
