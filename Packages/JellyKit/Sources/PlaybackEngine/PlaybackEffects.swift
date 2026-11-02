import Foundation
import LibraryKit

/// What a stop does to the local state (data-plan §5.1 rule 5).
public protocol PlaybackEffects: Sendable {
    /// Immediately at stop, before any network: patch the item's watched state and resume position.
    func playbackStopped(itemId: String, positionTicks: Int64) async
    /// Once the server accepted the `Stopped` report (live or replayed): lists that show it are stale.
    func stopReportAccepted(itemId: String) async
}

/// Applies the effects to a `LibraryStore`.
public struct LibraryStoreEffects: PlaybackEffects {
    /// Everything a finished playback can change, as `isAffectedQuery` plus series and episodes (§3.1 note 1).
    public static let affectedKinds: Set<ResourceKind> = [
        .continueWatching, .nextUp, .seriesNextUp, .adjacentEpisode, .detail, .children,
        .recentlyAdded, .latestMovies, .latestTV, .shelfPage,
    ]

    private let store: LibraryStore
    private let thresholds: @Sendable () async -> ResumeThresholds?
    private let now: @Sendable () -> Date

    /// `thresholds` reads the server configuration; nil (not stated) means the local patch is skipped
    /// and the server's answer, after `markStale`, is the only truth.
    public init(
        store: LibraryStore, thresholds: @escaping @Sendable () async -> ResumeThresholds?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.thresholds = thresholds
        self.now = now
    }

    public func playbackStopped(itemId: String, positionTicks: Int64) async {
        guard let thresholds = await thresholds() else { return }
        let date = now()
        await patch(itemId: itemId, positionTicks: positionTicks, thresholds: thresholds, now: date)
    }

    public func stopReportAccepted(itemId: String) async {
        await store.markStale(Self.affectedKinds)
    }

    @MainActor
    private func patch(itemId: String, positionTicks: Int64, thresholds: ResumeThresholds, now: Date) {
        let runtime = store.items[itemId]?.runtimeTicks
        store.patchUserData(itemId) {
            ResumeRule.apply(to: $0, positionTicks: positionTicks, runtimeTicks: runtime, thresholds: thresholds, now: now)
        }
    }
}
