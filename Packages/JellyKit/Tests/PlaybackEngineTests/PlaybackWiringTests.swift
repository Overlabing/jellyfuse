import Foundation
import LibraryKit
import Testing
@testable import PlaybackEngine

private struct NoSnapshots: SnapshotStorage {
    func read(owner: String) throws -> Data? { nil }
    func write(_ data: Data, owner: String) throws {}
    func remove(owner: String) throws {}
}

private actor StubLibraryAPI: LibraryAPI {
    static let runtime: Int64 = 100 * PlaybackSnapshot.ticksPerSecond * 60
    func resume(limit: Int) async throws -> [LibraryEntry] {
        [LibraryEntry(item: MediaItem(id: "movie", name: "Movie", runtimeTicks: Self.runtime))]
    }
    func nextUp(limit: Int) async throws -> [LibraryEntry] { [] }
    func libraries() async throws -> [Library] { [] }
    func latest(in libraryId: String, limit: Int) async throws -> [LibraryEntry] { [] }
    func recentlyAdded(in libraryId: String, limit: Int) async throws -> [LibraryEntry] { [] }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private struct Offline: Error {}

@Suite struct PositionTicksTests {
    @Test func secondsBecomeTicks() {
        #expect(PlaybackSnapshot.ticks(seconds: 0) == 0)
        #expect(PlaybackSnapshot.ticks(seconds: 1) == 10_000_000)
        #expect(PlaybackSnapshot.ticks(seconds: 42.5) == 425_000_000)
    }

    @Test func nonsensePositionsAreZero() {
        #expect(PlaybackSnapshot.ticks(seconds: -3) == 0)
        #expect(PlaybackSnapshot.ticks(seconds: .nan) == 0)
        #expect(PlaybackSnapshot.ticks(seconds: .infinity) == 0)
    }
}

@Suite struct ResumeThresholdsCacheTests {
    private let thresholds = ResumeThresholds(minPercent: 5, maxPercent: 90, minDurationSeconds: 300)

    @Test func fetchesOnceOnSuccess() async {
        let counter = Counter()
        let thresholds = thresholds
        let cache = ResumeThresholdsCache { counter.increment(); return thresholds }
        #expect(await cache.value() == thresholds)
        #expect(await cache.value() == thresholds)
        #expect(counter.count == 1)
    }

    @Test func aFailureIsRetriedNotCached() async {
        let counter = Counter()
        let thresholds = thresholds
        let cache = ResumeThresholdsCache {
            counter.increment()
            if counter.count == 1 { throw Offline() }
            return thresholds
        }
        #expect(await cache.value() == nil)
        #expect(await cache.value() == thresholds)
        #expect(counter.count == 2)
    }
}

@MainActor @Suite struct LibraryStoreEffectsTests {
    private let thresholds = ResumeThresholds(minPercent: 5, maxPercent: 90, minDurationSeconds: 300)

    private func store() -> LibraryStore {
        LibraryStore(owner: "srv|u1", api: StubLibraryAPI(), storage: NoSnapshots())
    }

    @Test func nilThresholdsSkipTheLocalPatch() async throws {
        let store = store()
        try await store.ensureFresh(.continueWatching)
        let effects = LibraryStoreEffects(store: store, thresholds: { nil })
        await effects.playbackStopped(itemId: "movie", positionTicks: 100)
        #expect(store.userData["movie"] == nil || store.userData["movie"]?.playbackPositionTicks == 0)
    }

    @Test func stopPatchesTheResumePositionAtOnce() async throws {
        let store = store()
        try await store.ensureFresh(.continueWatching)
        let thresholds = thresholds
        let effects = LibraryStoreEffects(store: store, thresholds: { thresholds })
        let position = 30 * 60 * PlaybackSnapshot.ticksPerSecond
        await effects.playbackStopped(itemId: "movie", positionTicks: position)
        #expect(store.userData["movie"]?.playbackPositionTicks == position)
        #expect(store.userData["movie"]?.played == false)
    }

    @Test func stoppingNearTheEndMarksItPlayedAndClearsTheResume() async throws {
        let store = store()
        try await store.ensureFresh(.continueWatching)
        let thresholds = thresholds
        let effects = LibraryStoreEffects(store: store, thresholds: { thresholds })
        await effects.playbackStopped(itemId: "movie", positionTicks: StubLibraryAPI.runtime - 10 * PlaybackSnapshot.ticksPerSecond)
        #expect(store.userData["movie"]?.played == true)
        #expect(store.userData["movie"]?.playbackPositionTicks == 0)
    }

    @Test func acceptedStopInvalidatesTheContinueWatchingShelf() async throws {
        let store = store()
        try await store.ensureFresh(.continueWatching)
        #expect(!store.isStale(.continueWatching))
        let effects = LibraryStoreEffects(store: store, thresholds: { nil })
        await effects.stopReportAccepted(itemId: "movie")
        #expect(store.isStale(.continueWatching))
    }
}
