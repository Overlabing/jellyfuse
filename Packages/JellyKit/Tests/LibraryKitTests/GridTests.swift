import Foundation
import JellyfinAPI
import Testing
@testable import LibraryKit

/// Sort / filter / scope -> SDK parameters, and the store's paginated grids.
@MainActor
@Suite struct GridTests {
    private func makeStore(_ api: FakeAPI, clock: Clock = Clock()) -> LibraryStore {
        LibraryStore(
            owner: "srv|u1", api: api, storage: temporaryStorage().0,
            now: { clock.now }, persistDelay: .milliseconds(10), retryDelays: [.zero, .zero]
        )
    }

    private func many(_ count: Int) -> [LibraryEntry] { (0..<count).map { entry("m\($0)") } }

    private func parameters(_ key: GridKey, start: Int = 0, limit: Int = 120) -> Paths.GetItemsParameters {
        key.query.parameters(userID: "u1", startIndex: start, limit: limit, imageTypes: [.primary])
    }

    // MARK: Mapping

    @Test func movieTabListsEveryMovieByNameAscending() {
        let p = parameters(GridKey(.library(.movies)))
        #expect(p.includeItemTypes == [.movie])
        #expect(p.sortBy == [.sortName])
        #expect(p.sortOrder == [.ascending])
        #expect(p.isRecursive == true)
        #expect(p.parentID == nil)
        #expect(p.isPlayed == nil && p.isFavorite == nil)
        #expect(p.enableTotalRecordCount == true)
    }

    @Test func seriesTabListsSeries() {
        #expect(parameters(GridKey(.library(.tvshows))).includeItemTypes == [.series])
    }

    @Test func paginationParametersCarryTheOffsetAndLimit() {
        let p = parameters(GridKey(.library(.movies)), start: 240, limit: 120)
        #expect(p.startIndex == 240)
        #expect(p.limit == 120)
        #expect(p.userID == "u1")
    }

    @Test(arguments: [
        (LibrarySortField.name, SortDirection.ascending, [ItemSortBy.sortName], [JellyfinAPI.SortOrder.ascending]),
        (.name, .descending, [.sortName], [.descending]),
        (.dateAdded, .descending, [.dateCreated, .sortName], [.descending, .ascending]),
        (.dateAdded, .ascending, [.dateCreated, .sortName], [.ascending, .ascending]),
        (.year, .descending, [.productionYear, .sortName], [.descending, .ascending]),
        (.rating, .descending, [.communityRating, .sortName], [.descending, .ascending]),
    ])
    func sortMapsToSortByAndOrder(field: LibrarySortField, direction: SortDirection, by: [ItemSortBy], order: [JellyfinAPI.SortOrder]) {
        let p = parameters(GridKey(.library(.movies), sort: LibrarySort(field, direction)))
        #expect(p.sortBy == by)
        #expect(p.sortOrder == order)
    }

    @Test func defaultDirectionIsNaturalPerField() {
        #expect(LibrarySort(.name).direction == .ascending)
        #expect(LibrarySort(.dateAdded).direction == .descending)
        #expect(LibrarySort(.year).direction == .descending)
        #expect(LibrarySort(.rating).direction == .descending)
    }

    @Test func filtersMapToPlayedAndFavorite() {
        let p = parameters(GridKey(.library(.movies), filter: LibraryFilter(unwatchedOnly: true, favoritesOnly: true)))
        #expect(p.isPlayed == false)
        #expect(p.isFavorite == true)
        let unwatched = parameters(GridKey(.library(.movies), filter: LibraryFilter(unwatchedOnly: true)))
        #expect(unwatched.isPlayed == false && unwatched.isFavorite == nil)
    }

    @Test func letterJumpOnlyAppliesToAZOrder() {
        let jump = parameters(GridKey(.library(.movies), startsAt: "M"))
        #expect(jump.nameStartsWithOrGreater == "M")
        let byYear = parameters(GridKey(.library(.movies), sort: LibrarySort(.year), startsAt: "M"))
        #expect(byYear.nameStartsWithOrGreater == nil)
        let descending = parameters(GridKey(.library(.movies), sort: LibrarySort(.name, .descending), startsAt: "M"))
        #expect(descending.nameStartsWithOrGreater == nil)
    }

    @Test func collectionsScopeQueriesBoxSetsOfTheCollectionsLibrary() {
        let p = parameters(GridKey(.collections(libraryId: "boxes")))
        #expect(p.includeItemTypes == [.boxSet])
        #expect(p.parentID == "boxes")
    }

    @Test func collectionScopeListsItsChildren() {
        let p = parameters(GridKey(.collection(id: "saga")))
        #expect(p.parentID == "saga")
        #expect(p.includeItemTypes == [.movie, .series])
    }

    @Test func personScopeQueriesCreditsByPersonId() {
        let p = parameters(GridKey(.person(id: "p1")))
        #expect(p.personIDs == ["p1"])
        #expect(p.parentID == nil)
        #expect(p.includeItemTypes == [.movie, .series])
        #expect(p.isRecursive == true)
    }

    @Test func eachSortFilterCombinationIsItsOwnKey() {
        let keys: Set<GridKey> = [
            GridKey(.library(.movies)), GridKey(.library(.movies), sort: LibrarySort(.year)),
            GridKey(.library(.movies), filter: LibraryFilter(favoritesOnly: true)), GridKey(.library(.movies), startsAt: "B"),
            GridKey(.library(.tvshows)),
        ]
        #expect(keys.count == 5)
    }

    // MARK: Pagination

    @Test func firstPageLoadsPageSizeItemsAndTheTotal() async throws {
        let api = FakeAPI()
        await api.setPaged(many(300))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        #expect(store.isStale(key))
        try await store.ensureGridFresh(key)
        #expect(store.gridEntries(key).count == LibraryStore.gridPageSize)
        #expect(store.gridTotal(key) == 300)
        #expect(!store.isGridComplete(key))
        #expect(!store.isStale(key))
        let queries = await api.itemQueries
        #expect(queries.count == 1 && queries[0].startIndex == 0 && queries[0].limit == LibraryStore.gridPageSize)
    }

    @Test func nextPagesAppendInOrderUntilTheEnd() async throws {
        let api = FakeAPI()
        await api.setPaged(many(250))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        try await store.loadNextGridPage(key)
        #expect(store.gridEntries(key).count == 240)
        #expect(store.gridEntries(key).map(\.item.id).prefix(3) == ["m0", "m1", "m2"])
        #expect(!store.isGridComplete(key))
        try await store.loadNextGridPage(key)
        #expect(store.gridEntries(key).count == 250)
        #expect(store.isGridComplete(key))
        // The end of the list: no further request.
        try await store.loadNextGridPage(key)
        #expect(await api.itemQueries.count == 3)
        #expect(await api.itemQueries.map(\.startIndex) == [0, 120, 240])
    }

    @Test func aListShorterThanAPageIsCompleteAtOnce() async throws {
        let api = FakeAPI()
        await api.setPaged(many(7))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        #expect(store.isGridComplete(key))
        try await store.loadNextGridPage(key)
        #expect(await api.itemQueries.count == 1)
    }

    @Test func emptyListIsCompleteAndEmpty() async throws {
        let api = FakeAPI()
        let store = makeStore(api)
        let key = GridKey(.person(id: "nobody"))
        try await store.ensureGridFresh(key)
        #expect(store.gridEntries(key).isEmpty)
        #expect(store.isGridComplete(key))
    }

    @Test func overlappingPagesAreDeduplicated() async throws {
        let api = FakeAPI()
        await api.setPaged(many(200))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        // Something is added in front between two pages: the second page repeats the last item of the first.
        await api.setPaged([entry("new")] + many(200))
        try await store.loadNextGridPage(key)
        let ids = store.gridEntries(key).map(\.item.id)
        #expect(ids.count == Set(ids).count)
        #expect(ids.count == 200, "the repeated item is not shown twice")
        #expect(store.gridTotal(key) == 201)
        #expect(store.isGridComplete(key))
    }

    @Test func loadNextBeforeTheFirstPageDoesNothing() async throws {
        let api = FakeAPI()
        await api.setPaged(many(10))
        let store = makeStore(api)
        try await store.loadNextGridPage(GridKey(.library(.movies)))
        #expect(await api.itemQueries.isEmpty)
    }

    @Test func staleGridStartsOverFromItsFirstPage() async throws {
        let api = FakeAPI()
        await api.setPaged(many(300))
        let clock = Clock()
        let store = makeStore(api, clock: clock)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        try await store.loadNextGridPage(key)
        clock.advance(120)
        try await store.ensureGridFresh(key)
        #expect(await api.itemQueries.count == 2, "fresh: no request")
        clock.advance(400)
        #expect(store.isStale(key))
        try await store.ensureGridFresh(key)
        #expect(store.gridEntries(key).count == LibraryStore.gridPageSize)
        #expect(await api.itemQueries.count == 3)
    }

    @Test func differentKeysKeepTheirOwnPages() async throws {
        let api = FakeAPI()
        await api.setPaged(many(300))
        let store = makeStore(api)
        let byName = GridKey(.library(.movies))
        let byYear = GridKey(.library(.movies), sort: LibrarySort(.year))
        try await store.ensureGridFresh(byName)
        try await store.loadNextGridPage(byName)
        try await store.ensureGridFresh(byYear)
        #expect(store.gridEntries(byName).count == 240)
        #expect(store.gridEntries(byYear).count == 120)
        #expect(await api.itemQueries.last?.query.sortBy == [.productionYear, .sortName])
    }

    @Test func concurrentLoadsShareOneRequest() async throws {
        let api = FakeAPI()
        await api.setPaged(many(300))
        await api.holdAnswers()
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        async let first: Void = store.ensureGridFresh(key)
        await api.waitUntilParked()
        async let second: Void = store.ensureGridFresh(key)
        await api.releaseAnswers()
        _ = try await (first, second)
        #expect(await api.callCount("items:0") == 1)
    }

    @Test func failedNextPageKeepsWhatIsLoadedAndCanRetry() async throws {
        let api = FakeAPI()
        await api.setPaged(many(300))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        await api.queueErrors([JellyfinError.http(500)])
        await #expect(throws: JellyfinError.self) { try await store.loadNextGridPage(key) }
        #expect(store.gridEntries(key).count == 120)
        try await store.loadNextGridPage(key)
        #expect(store.gridEntries(key).count == 240)
    }

    @Test func gridEntriesFollowSharedUserData() async throws {
        let api = FakeAPI()
        await api.setPaged(many(3))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        store.patchUserData("m1") { var d = $0; d.played = true; return d }
        #expect(store.gridEntries(key)[1].userData.played)
    }

    @Test func markStaleOfShelfPagesMakesGridsStale() async throws {
        let api = FakeAPI()
        await api.setPaged(many(3))
        let store = makeStore(api)
        let key = GridKey(.library(.movies))
        try await store.ensureGridFresh(key)
        store.markStale([.shelfPage])
        #expect(store.isStale(key))
    }

    @Test func gridsAreNeverPersisted() async throws {
        let api = FakeAPI()
        await api.setPaged(many(3))
        let (storage, _) = temporaryStorage()
        let clock = Clock()
        let store = LibraryStore(owner: "srv|u1", api: api, storage: storage, now: { clock.now }, persistDelay: .milliseconds(10))
        try await store.ensureGridFresh(GridKey(.library(.movies)))
        store.persistNow()
        let reborn = LibraryStore(owner: "srv|u1", api: api, storage: storage, now: { clock.now })
        #expect(reborn.gridEntries(GridKey(.library(.movies))).isEmpty)
        #expect(reborn.isStale(GridKey(.library(.movies))))
    }

    // MARK: Collections allowlist

    @Test func boxsetsLibraryJoinsTheAllowlistButNotTheHome() {
        let views = [
            BaseItemDto(collectionType: .movies, id: "films", name: "Films"),
            BaseItemDto(collectionType: .boxsets, id: "boxes", name: "Collections"),
            BaseItemDto(collectionType: .music, id: "music", name: "Musique"),
        ]
        let libraries = Library.videoLibraries(from: views)
        #expect(libraries.map(\.id) == ["films", "boxes"])
        #expect(libraries.filter(\.showsOnHome).map(\.id) == ["films"])
    }

    @Test func storeFindsTheCollectionsLibrary() async throws {
        let api = FakeAPI()
        await api.setLibraries([Library(id: "films", name: "Films", kind: .movies), Library(id: "boxes", name: "Collections", kind: .boxsets)])
        let store = makeStore(api)
        try await store.ensureLibrariesFresh()
        #expect(store.libraries(of: .boxsets).map(\.id) == ["boxes"])
        #expect(store.libraries(of: .tvshows).isEmpty)
    }

    @Test func boxSetItemsMapToTheBoxSetKind() {
        #expect(MediaItem.Kind(kind: .boxSet) == .boxSet)
    }
}
