import Foundation
import Testing
@testable import LibraryKit

@MainActor
@Suite struct SnapshotTests {
    private func store(
        _ api: FakeAPI, owner: String, storage: FileSnapshotStorage, clock: Clock = Clock()
    ) -> LibraryStore {
        LibraryStore(
            owner: owner, api: api, storage: storage,
            now: { clock.now }, persistDelay: .milliseconds(10), retryDelays: []
        )
    }

    private func loaded(owner: String, storage: FileSnapshotStorage, ids: [String], clock: Clock = Clock()) async throws {
        let api = FakeAPI()
        await api.setResume(ids.map { entry($0, position: 300) })
        let s = store(api, owner: owner, storage: storage, clock: clock)
        try await s.ensureFresh(.continueWatching)
        s.persistNow()
    }

    @Test func roundTripRestoresShelvesItemsAndUserDataAsStale() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try await loaded(owner: "srv|u1", storage: storage, ids: ["a", "b"])

        let fresh = store(FakeAPI(), owner: "srv|u1", storage: storage)
        #expect(fresh.shelf(.continueWatching) == ["a", "b"])
        #expect(fresh.items["a"]?.name == "Item a")
        #expect(fresh.userData["b"]?.playbackPositionTicks == 300)
        #expect(fresh.isStale(.continueWatching))
    }

    @Test func hydratedShelfRevalidatesOnEnsureFresh() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try await loaded(owner: "srv|u1", storage: storage, ids: ["a"])

        let api = FakeAPI()
        await api.setResume([entry("z")])
        let fresh = store(api, owner: "srv|u1", storage: storage)
        try await fresh.ensureFresh(.continueWatching)
        #expect(await api.callCount("resume") == 1)
        #expect(fresh.shelf(.continueWatching) == ["z"])
    }

    @Test func writeIsThrottledAfterALoad() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = FakeAPI()
        await api.setResume([entry("a")])
        let s = store(api, owner: "srv|u1", storage: storage)
        try await s.ensureFresh(.continueWatching)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try storage.read(owner: "srv|u1") != nil)
    }

    @Test func onlyReferencedItemsArePersisted() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let api = FakeAPI()
        await api.setResume([entry("a")])
        let s = store(api, owner: "srv|u1", storage: storage)
        try await s.ensureFresh(.continueWatching)
        try await s.mutateUserData(["ghost"], invalidating: []) { var d = $0; d.played = true; return d } call: {}
        s.persistNow()
        let again = store(FakeAPI(), owner: "srv|u1", storage: storage)
        #expect(again.items.keys.sorted() == ["a"])
        #expect(again.userData["ghost"] == nil)
    }

    @Test func otherSchemaVersionIsDiscardedAndDeleted() throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = LibrarySnapshot(
            schemaVersion: LibrarySnapshot.currentVersion + 1, savedAt: Clock().now, owner: "srv|u1",
            libraries: [], shelves: [.init(key: .continueWatching, ids: ["a"])], items: ["a": entry("a").item], userData: [:]
        )
        try SnapshotStore(storage: storage).save(old)
        let fresh = store(FakeAPI(), owner: "srv|u1", storage: storage)
        #expect(fresh.shelf(.continueWatching).isEmpty)
        #expect(try storage.read(owner: "srv|u1") == nil)
    }

    @Test func perLibraryShelvesAndLibraryListRoundTripAndComeBackStale() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let films = Library(id: "films", name: "Films", kind: .movies)
        let api = FakeAPI()
        await api.setLibraries([films])
        await api.setLatest([entry("f1"), entry("f2")], in: "films")
        await api.setGrid([entry("g1")], in: "films")
        let s = store(api, owner: "srv|u1", storage: storage)
        try await s.ensureLibrariesFresh()
        try await s.ensureFresh(.latestIn(libraryId: "films"))
        try await s.ensureFresh(.recentGrid(libraryId: "films"))
        s.persistNow()

        let again = store(FakeAPI(), owner: "srv|u1", storage: storage)
        #expect(again.libraries == [films])
        #expect(again.isLibrariesStale())
        #expect(again.shelf(.latestIn(libraryId: "films")) == ["f1", "f2"])
        #expect(again.isStale(.latestIn(libraryId: "films")))
        // The grid is memory only.
        #expect(again.shelf(.recentGrid(libraryId: "films")).isEmpty)
        #expect(again.items["g1"] == nil)
    }

    @Test func snapshotFromBeforePerLibraryShelvesIsIgnoredAndDeleted() throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        // Shape written by v1: string shelf keys, no library list.
        let legacy = """
        {"schemaVersion":1,"savedAt":"2027-01-15T08:00:00Z","owner":"srv|u1",
         "shelves":[{"key":"recentlyAdded","ids":["a"]}],"items":{},"userData":{}}
        """
        try storage.write(Data(legacy.utf8), owner: "srv|u1")
        let fresh = store(FakeAPI(), owner: "srv|u1", storage: storage)
        #expect(fresh.libraries.isEmpty)
        #expect(fresh.isLibrariesStale())
        #expect(try storage.read(owner: "srv|u1") == nil)
    }

    @Test func snapshotOlderThanThirtyDaysIsDiscarded() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        try await loaded(owner: "srv|u1", storage: storage, ids: ["a"], clock: clock)

        clock.advance(29 * 24 * 3600)
        #expect(store(FakeAPI(), owner: "srv|u1", storage: storage, clock: clock).shelf(.continueWatching) == ["a"])
        clock.advance(2 * 24 * 3600)
        #expect(store(FakeAPI(), owner: "srv|u1", storage: storage, clock: clock).shelf(.continueWatching).isEmpty)
        #expect(try storage.read(owner: "srv|u1") == nil)
    }

    @Test func corruptSnapshotIsIgnored() throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.write(Data("not json".utf8), owner: "srv|u1")
        #expect(store(FakeAPI(), owner: "srv|u1", storage: storage).shelf(.continueWatching).isEmpty)
    }

    @Test func foreignOwnerInsideAFileIsRejected() throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        let foreign = LibrarySnapshot(
            schemaVersion: LibrarySnapshot.currentVersion, savedAt: Clock().now, owner: "srv|someone-else",
            libraries: [], shelves: [.init(key: .continueWatching, ids: ["a"])], items: ["a": entry("a").item], userData: [:]
        )
        try storage.write(JSONEncoder().encode(foreign), owner: "srv|u1")
        #expect(store(FakeAPI(), owner: "srv|u1", storage: storage).shelf(.continueWatching).isEmpty)
    }

    // MARK: Owner scoping

    @Test func eachOwnerSeesOnlyItsOwnSnapshot() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try await loaded(owner: "srv|alice", storage: storage, ids: ["a1"])
        try await loaded(owner: "srv|bob", storage: storage, ids: ["b1", "b2"])

        #expect(store(FakeAPI(), owner: "srv|alice", storage: storage).shelf(.continueWatching) == ["a1"])
        #expect(store(FakeAPI(), owner: "srv|bob", storage: storage).shelf(.continueWatching) == ["b1", "b2"])
        #expect(store(FakeAPI(), owner: "other|alice", storage: storage).shelf(.continueWatching).isEmpty)
    }

    @Test func switchingUserKeepsThePreviousOwnersSnapshotOnDisk() async throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try await loaded(owner: "srv|alice", storage: storage, ids: ["a1"])
        // Switch: the alice store is dropped, a bob store is built.
        let bob = store(FakeAPI(), owner: "srv|bob", storage: storage)
        #expect(bob.shelf(.continueWatching).isEmpty)
        // Back to alice: instant, stale, from disk.
        let alice = store(FakeAPI(), owner: "srv|alice", storage: storage)
        #expect(alice.shelf(.continueWatching) == ["a1"])
        #expect(alice.isStale(.continueWatching))
    }

    @Test func storageKeepsAtMostFiveOwnersEvictingTheOldest() throws {
        let (storage, root) = temporaryStorage(maxOwners: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.write(Data("1".utf8), owner: "o1")
        Thread.sleep(forTimeInterval: 0.05)
        try storage.write(Data("2".utf8), owner: "o2")
        Thread.sleep(forTimeInterval: 0.05)
        try storage.write(Data("3".utf8), owner: "o3")
        #expect(try storage.read(owner: "o1") == nil)
        #expect(try storage.read(owner: "o2") != nil)
        #expect(try storage.read(owner: "o3") != nil)
    }

    @Test func removeDeletesOnlyThatOwner() throws {
        let (storage, root) = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.write(Data("1".utf8), owner: "o1")
        try storage.write(Data("2".utf8), owner: "o2")
        try storage.remove(owner: "o1")
        #expect(try storage.read(owner: "o1") == nil)
        #expect(try storage.read(owner: "o2") != nil)
    }
}
