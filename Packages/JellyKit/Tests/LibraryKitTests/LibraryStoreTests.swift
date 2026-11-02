import Foundation
import Testing
@testable import LibraryKit

@MainActor
@Suite struct LibraryStoreTests {
    struct Boom: Error {}

    private func makeStore(
        _ api: FakeAPI, clock: Clock = Clock(), owner: String = "srv|u1",
        storage: any SnapshotStorage = temporaryStorage().0, reachability: ServerReachability? = nil
    ) -> LibraryStore {
        LibraryStore(
            owner: owner, api: api, storage: storage, reachability: reachability,
            now: { clock.now }, persistDelay: .milliseconds(10), retryDelays: [.zero, .zero]
        )
    }

    // MARK: Freshness

    @Test func neverLoadedShelfIsStaleAndLoadsOnEnsureFresh() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a", position: 250), entry("b")])
        let store = makeStore(api)
        #expect(store.isStale(.continueWatching))
        try await store.ensureFresh(.continueWatching)
        #expect(store.shelf(.continueWatching) == ["a", "b"])
        #expect(store.items["a"]?.name == "Item a")
        #expect(store.userData["a"]?.playbackPositionTicks == 250)
        #expect(store.entries(.continueWatching).count == 2)
        #expect(!store.isStale(.continueWatching))
    }

    @Test func freshShelfIsNotRefetchedStaleOneIs() async throws {
        let api = FakeAPI()
        let clock = Clock()
        let store = makeStore(api, clock: clock)
        try await store.ensureFresh(.continueWatching)
        clock.advance(30)
        try await store.ensureFresh(.continueWatching)
        #expect(await api.callCount("resume") == 1)
        clock.advance(31)
        #expect(store.isStale(.continueWatching))
        try await store.ensureFresh(.continueWatching)
        #expect(await api.callCount("resume") == 2)
    }

    @Test func forceRefetchesAFreshShelf() async throws {
        let api = FakeAPI()
        let store = makeStore(api)
        try await store.ensureFresh(.nextUp)
        try await store.ensureFresh(.nextUp, force: true)
        #expect(await api.callCount("nextUp") == 2)
    }

    @Test func markStaleForcesRefetchOfMatchingKindsOnly() async throws {
        let api = FakeAPI()
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        try await store.ensureFresh(.latestIn(libraryId: "films"))
        store.markStale([.continueWatching])
        #expect(store.isStale(.continueWatching))
        #expect(!store.isStale(.latestIn(libraryId: "films")))
    }

    // MARK: Loading plumbing

    @Test func concurrentEnsureFreshSharesOneRequest() async throws {
        let api = FakeAPI()
        await api.holdAnswers()
        let store = makeStore(api)
        async let first: Void = store.ensureFresh(.continueWatching)
        await api.waitUntilParked()
        async let second: Void = store.ensureFresh(.continueWatching)
        await api.releaseAnswers()
        try await first
        try await second
        #expect(await api.callCount("resume") == 1)
    }

    @Test func networkErrorsRetryTwiceThenSucceed() async throws {
        let api = FakeAPI()
        await api.queueErrors([URLError(.timedOut), URLError(.notConnectedToInternet)])
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        #expect(await api.callCount("resume") == 3)
    }

    @Test func networkErrorsGiveUpAfterTwoRetries() async {
        let api = FakeAPI()
        await api.queueErrors([URLError(.timedOut), URLError(.timedOut), URLError(.timedOut)])
        let store = makeStore(api)
        await #expect(throws: URLError.self) { try await store.ensureFresh(.continueWatching) }
        #expect(await api.callCount("resume") == 3)
        #expect(store.isStale(.continueWatching))
    }

    @Test func httpErrorsAreNeverRetried() async {
        let api = FakeAPI()
        await api.queueErrors([JellyfinError.http(500)])
        let store = makeStore(api)
        await #expect(throws: JellyfinError.self) { try await store.ensureFresh(.continueWatching) }
        #expect(await api.callCount("resume") == 1)
    }

    @Test func offlineEnsureFreshLaunchesNothingAndDoesNotFail() async throws {
        let api = FakeAPI()
        let reachability = ServerReachability(probe: { false })
        await reachability.check()
        #expect(!reachability.isOnline)
        let store = makeStore(api, reachability: reachability)
        try await store.ensureFresh(.continueWatching)
        #expect(await api.callCount("resume") == 0)
    }

    @Test func failureMarksServerUnreachableAndSuccessRestoresIt() async throws {
        let api = FakeAPI()
        let reachability = ServerReachability(probe: { true })
        let store = makeStore(api, reachability: reachability)
        await api.queueErrors([URLError(.cannotConnectToHost), URLError(.cannotConnectToHost), URLError(.cannotConnectToHost)])
        await #expect(throws: URLError.self) { try await store.ensureFresh(.continueWatching) }
        #expect(reachability.connectivity != .online)
        reachability.reportSuccess()
        #expect(reachability.isOnline)
    }

    // MARK: Optimistic mutation

    @Test func mutationPatchesLocallyAndMarksStaleOnSuccessOnly() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a", position: 500)])
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        try await store.ensureFresh(.latestIn(libraryId: "films"))

        var duringCall: UserData?
        try await store.mutateUserData(["a"], invalidating: [.continueWatching]) {
            var data = $0
            data.played = true
            return data
        } call: {
            duringCall = store.userData["a"]
        }
        #expect(duringCall?.played == true)
        #expect(store.userData["a"]?.played == true)
        #expect(store.isStale(.continueWatching))
        #expect(!store.isStale(.latestIn(libraryId: "films")))
    }

    @Test func failedMutationRestoresTheSnapshotWithoutInvalidating() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a", position: 500), entry("b")])
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        let before = store.userData

        await #expect(throws: Boom.self) {
            try await store.mutateUserData(["a", "b"], invalidating: [.continueWatching]) {
                var data = $0
                data.isFavorite = true
                return data
            } call: {
                #expect(store.userData["a"]?.isFavorite == true)
                throw Boom()
            }
        }
        #expect(store.userData == before)
        #expect(!store.isStale(.continueWatching))
    }

    @Test func rollbackRestoresAbsenceOfEntry() async {
        let store = makeStore(FakeAPI())
        await #expect(throws: Boom.self) {
            try await store.mutateUserData(["ghost"], invalidating: []) { var d = $0; d.played = true; return d } call: { throw Boom() }
        }
        #expect(store.userData["ghost"] == nil)
    }

    @Test func mutationCancelsAnInflightLoadSoItCannotOverwriteThePatch() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a", position: 500)])
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        await api.holdAnswers()
        async let reload: Void = store.ensureFresh(.continueWatching, force: true)
        await api.waitUntilParked()

        try await store.mutateUserData(["a"], invalidating: [.continueWatching]) {
            var data = $0
            data.played = true
            return data
        } call: {}
        await api.releaseAnswers()
        try await reload
        #expect(store.userData["a"]?.played == true)
    }

    // MARK: Normalisation

    @Test func onePatchReachesEveryShelfThatListsTheItem() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a")])
        let store = makeStore(api)
        try await store.ensureFresh(.continueWatching)
        try await store.ensureFresh(.nextUp)
        try await store.mutateUserData(["a"], invalidating: []) { var d = $0; d.played = true; return d } call: {}
        #expect(store.entries(.continueWatching).first?.userData.played == true)
    }
}

@MainActor
@Suite struct LibraryStorePatchTests {
    @Test func patchUserDataIsLocalOnlyAndCancelsInFlightLoads() async throws {
        let api = FakeAPI()
        await api.setResume([entry("a", position: 100)])
        let store = LibraryStore(owner: "srv|u1", api: api, storage: temporaryStorage().0, persistDelay: .milliseconds(10), retryDelays: [])
        try await store.ensureFresh(.continueWatching)
        store.patchUserData("a") { var data = $0; data.playbackPositionTicks = 500; return data }
        #expect(store.userData["a"]?.playbackPositionTicks == 500)
        #expect(!store.isStale(.continueWatching))
        store.patchUserData("unknown") { var data = $0; data.played = true; return data }
        #expect(store.userData["unknown"] == nil)
    }
}

@MainActor
@Suite struct LibraryShelvesTests {
    private func makeStore(_ api: FakeAPI, clock: Clock = Clock()) -> LibraryStore {
        LibraryStore(
            owner: "srv|u1", api: api, storage: temporaryStorage().0,
            now: { clock.now }, persistDelay: .milliseconds(10), retryDelays: []
        )
    }

    @Test func eachLibraryHasItsOwnShelfLoadedWithItsId() async throws {
        let api = FakeAPI()
        await api.setLatest([entry("f1")], in: "films")
        await api.setLatest([entry("s1"), entry("s2")], in: "series")
        let store = makeStore(api)
        try await store.ensureFresh(.latestIn(libraryId: "films"))
        try await store.ensureFresh(.latestIn(libraryId: "series"))
        #expect(store.shelf(.latestIn(libraryId: "films")) == ["f1"])
        #expect(store.shelf(.latestIn(libraryId: "series")) == ["s1", "s2"])
        #expect(store.isStale(.latestIn(libraryId: "other")))
        #expect(await api.callCount("latest:films") == 1)
        #expect(await api.callCount("latest:series") == 1)
    }

    @Test func libraryShelvesShareTheRecentlyAddedStalenessAndMarkStaleHitsAllOfThem() async throws {
        let clock = Clock()
        let api = FakeAPI()
        let store = makeStore(api, clock: clock)
        try await store.ensureFresh(.latestIn(libraryId: "films"))
        try await store.ensureFresh(.latestIn(libraryId: "series"))
        clock.advance(299)
        #expect(!store.isStale(.latestIn(libraryId: "films")))
        clock.advance(2)
        #expect(store.isStale(.latestIn(libraryId: "films")))

        try await store.ensureFresh(.latestIn(libraryId: "films"))
        store.markStale([.recentlyAdded])
        #expect(store.isStale(.latestIn(libraryId: "films")))
        #expect(store.isStale(.latestIn(libraryId: "series")))
    }

    @Test func gridLoadsAFullPageAndHasItsOwnKey() async throws {
        let api = FakeAPI()
        await api.setGrid([entry("a"), entry("b"), entry("c")], in: "films")
        let store = makeStore(api)
        try await store.ensureFresh(.recentGrid(libraryId: "films"))
        #expect(store.shelf(.recentGrid(libraryId: "films")) == ["a", "b", "c"])
        #expect(store.shelf(.latestIn(libraryId: "films")).isEmpty)
        #expect(await api.callCount("grid:films") == 1)
    }

    @Test func libraryListUsesTheViewsStalenessAndIsSharedWhileInFlight() async throws {
        let clock = Clock()
        let api = FakeAPI()
        let films = Library(id: "films", name: "Films", kind: .movies)
        await api.setLibraries([films])
        let store = makeStore(api, clock: clock)
        #expect(store.isLibrariesStale())
        try await store.ensureLibrariesFresh()
        #expect(store.libraries == [films])
        try await store.ensureLibrariesFresh()
        #expect(await api.callCount("libraries") == 1)
        clock.advance(3601)
        #expect(store.isLibrariesStale())
        store.markStale([.views])
        try await store.ensureLibrariesFresh()
        #expect(await api.callCount("libraries") == 2)
        #expect(ResourceKind.views.staleTime == .seconds(3600))
    }

    @Test func markStaleOfViewsInvalidatesTheLibraryList() async throws {
        let api = FakeAPI()
        let store = makeStore(api)
        try await store.ensureLibrariesFresh()
        #expect(!store.isLibrariesStale())
        store.markStale([.continueWatching])
        #expect(!store.isLibrariesStale())
        store.markStale([.views])
        #expect(store.isLibrariesStale())
    }

    @Test func libraryListFailureLeavesTheCachedListInPlace() async throws {
        let api = FakeAPI()
        let films = Library(id: "films", name: "Films", kind: .movies)
        await api.setLibraries([films])
        let store = makeStore(api)
        try await store.ensureLibrariesFresh()
        await api.queueErrors([JellyfinError.http(500)])
        await #expect(throws: JellyfinError.self) { try await store.ensureLibrariesFresh(force: true) }
        #expect(store.libraries == [films])
    }
}
