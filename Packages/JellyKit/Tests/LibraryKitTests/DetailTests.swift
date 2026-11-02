import Foundation
import JellyfinAPI
import Testing
@testable import LibraryKit

@Suite struct DetailParsingTests {
    @Test func movieDetailCarriesMetadataAndImageTags() throws {
        let dto = BaseItemDto(
            backdropImageTags: ["bd1", "bd2"], communityRating: 7.8, genres: ["Drame", "Thriller"], id: "m1",
            imageTags: ["Primary": "p1", "Logo": "l1"], name: "Nocturne", officialRating: "TP",
            overview: "Une nuit.", productionYear: 2025, runTimeTicks: 76_800_000_000, type: .movie
        )
        let detail = try #require(ItemDetail(dto: dto))
        #expect(detail.item.id == "m1")
        #expect(detail.item.kind == .movie)
        #expect(detail.item.primaryImageTag == "p1")
        #expect(detail.overview == "Une nuit.")
        #expect(detail.productionYear == 2025)
        #expect(detail.communityRating.map { abs($0 - 7.8) < 0.001 } == true)
        #expect(detail.officialRating == "TP")
        #expect(detail.genres == ["Drame", "Thriller"])
        #expect(detail.backdropImageTag == "bd1")
        #expect(detail.logoImageTag == "l1")
        #expect(detail.endYear == nil)
    }

    @Test func missingLogoAndBackdropStayNil() throws {
        let detail = try #require(ItemDetail(dto: BaseItemDto(id: "m2", imageTags: ["Primary": "p"], name: "Sans logo", type: .movie)))
        #expect(detail.logoImageTag == nil)
        #expect(detail.backdropImageTag == nil)
        #expect(detail.genres.isEmpty)
    }

    @Test func endedSeriesExposesItsLastYearContinuingOneDoesNot() throws {
        let end = Date(timeIntervalSince1970: 1_750_000_000) // 2025
        let ended = try #require(ItemDetail(dto: BaseItemDto(endDate: end, id: "s1", name: "S", productionYear: 2022, status: "Ended", type: .series)))
        #expect(ended.endYear == 2025)
        let running = try #require(ItemDetail(dto: BaseItemDto(endDate: end, id: "s2", name: "S", status: "Continuing", type: .series)))
        #expect(running.endYear == nil)
    }

    @Test func peopleKeepActorsAndDirectorsInServerOrder() throws {
        let dto = BaseItemDto(
            id: "m1", name: "Nocturne",
            people: [
                BaseItemPerson(id: "p1", name: "Inès Marchand", primaryImageTag: "img", role: "Léa", type: .actor),
                BaseItemPerson(id: "p2", name: "Salomé Ricard", role: "", type: .director),
                BaseItemPerson(id: "p3", name: "Compositeur", type: .composer),
                BaseItemPerson(id: "p4", name: "", type: .actor),
                BaseItemPerson(name: "Sans id", type: .actor),
            ],
            type: .movie
        )
        let detail = try #require(ItemDetail(dto: dto))
        #expect(detail.people == [
            Person(id: "p1", name: "Inès Marchand", kind: .actor, role: "Léa", primaryImageTag: "img"),
            Person(id: "p2", name: "Salomé Ricard", kind: .director),
        ])
    }

    @Test func itemWithoutPeopleHasNone() throws {
        #expect(try #require(ItemDetail(dto: BaseItemDto(id: "m1", name: "x", type: .movie))).people.isEmpty)
    }

    @Test func itemWithoutIdIsRejected() {
        #expect(ItemDetail(dto: BaseItemDto(name: "x")) == nil)
    }

    @Test func episodeEntryKeepsSeasonLinksAndUserData() throws {
        let dto = BaseItemDto(
            id: "e1", indexNumber: 5, name: "Fréquence zéro", parentIndexNumber: 2, seasonID: "se2", seriesID: "s1", seriesName: "Fréquences",
            type: .episode, userData: UserItemDataDto(isFavorite: false, isPlayed: false, key: "k", playbackPositionTicks: 300)
        )
        let entry = try #require(LibraryEntry(dto: dto))
        #expect(entry.item.kind == .episode)
        #expect(entry.item.seriesId == "s1")
        #expect(entry.item.seasonId == "se2")
        #expect(entry.item.indexNumber == 5)
        #expect(entry.item.parentIndexNumber == 2)
        #expect(entry.userData.playbackPositionTicks == 300)
    }

    @Test func itemWithItsOwnLogoCarriesTheTagOnly() throws {
        let dto = BaseItemDto(id: "m1", imageTags: ["Primary": "p", "Logo": "lg"], name: "x", type: .movie)
        let item = try #require(LibraryEntry(dto: dto)).item
        #expect(item.logoImageTag == "lg")
        #expect(item.logoItemId == nil)
    }

    @Test func episodeFallsBackToTheParentLogo() throws {
        let dto = BaseItemDto(
            id: "e1", imageTags: ["Primary": "p"], name: "x", parentLogoImageTag: "plg", parentLogoItemID: "s1", seriesID: "s1", type: .episode
        )
        let item = try #require(LibraryEntry(dto: dto)).item
        #expect(item.logoImageTag == "plg")
        #expect(item.logoItemId == "s1")
    }

    @Test func parentLogoWithoutItsCarrierIsIgnoredAndNoLogoStaysNil() throws {
        let orphan = BaseItemDto(id: "e1", name: "x", parentLogoImageTag: "plg", type: .episode)
        #expect(try #require(LibraryEntry(dto: orphan)).item.logoImageTag == nil)
        let none = try #require(LibraryEntry(dto: BaseItemDto(id: "m1", name: "x", type: .movie))).item
        #expect(none.logoImageTag == nil && none.logoItemId == nil)
    }

    @Test func unsupportedKindsHaveNoKind() throws {
        let entry = try #require(LibraryEntry(dto: BaseItemDto(id: "x", name: "x", type: .boxSet)))
        #expect(entry.item.kind == nil)
    }

    @Test func itemsFromAnOlderSnapshotDecodeWithoutTheNewFields() throws {
        let json = #"{"id":"a","name":"A","primaryImageTag":"t","runtimeTicks":5}"#
        let item = try JSONDecoder().decode(MediaItem.self, from: Data(json.utf8))
        #expect(item.kind == nil)
        #expect(item.seriesId == nil)
        #expect(item.logoImageTag == nil)
    }
}

@MainActor
@Suite struct DetailStoreTests {
    struct Boom: Error {}

    private func makeStore(_ api: FakeAPI, clock: Clock = Clock()) -> LibraryStore {
        LibraryStore(
            owner: "srv|u1", api: api, storage: temporaryStorage().0,
            now: { clock.now }, persistDelay: .milliseconds(10), retryDelays: [.zero, .zero]
        )
    }

    private func movie(_ id: String = "m1") -> ItemDetail {
        ItemDetail(item: MediaItem(id: id, name: "Nocturne", kind: .movie), overview: "Une nuit.", logoImageTag: "l1")
    }

    private func episode(_ id: String, season: String, number: Int, position: Int64 = 0) -> LibraryEntry {
        LibraryEntry(
            item: MediaItem(id: id, name: "Ep \(number)", runtimeTicks: 1000, kind: .episode, seriesId: "s1", seasonId: season, indexNumber: number, parentIndexNumber: 1),
            userData: UserData(played: false, playbackPositionTicks: position, playCount: 0, isFavorite: false, lastPlayedDate: nil)
        )
    }

    @Test func detailLoadsOnceWhileFreshThenAgainWhenStale() async throws {
        let api = FakeAPI()
        await api.setDetail(movie(), userData: UserData(played: false, playbackPositionTicks: 40, playCount: 0, isFavorite: true, lastPlayedDate: nil))
        let clock = Clock()
        let store = makeStore(api, clock: clock)
        #expect(store.detail("m1") == nil)
        try await store.ensureDetailFresh("m1")
        try await store.ensureDetailFresh("m1")
        #expect(await api.callCount("detail:m1") == 1)
        #expect(store.detail("m1")?.logoImageTag == "l1")
        #expect(store.userData["m1"]?.isFavorite == true)
        #expect(store.userData["m1"]?.playbackPositionTicks == 40)
        clock.advance(121)
        try await store.ensureDetailFresh("m1")
        #expect(await api.callCount("detail:m1") == 2)
    }

    @Test func detailFailureLeavesNothingAndRetries() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        await api.queueErrors([Boom()])
        let store = makeStore(api)
        await #expect(throws: Boom.self) { try await store.ensureDetailFresh("m1") }
        #expect(store.detail("m1") == nil)
        try await store.ensureDetailFresh("m1")
        #expect(store.detail("m1") != nil)
    }

    @Test func seriesLoadsSeasonsAndEpisodesInServerOrderWithProgress() async throws {
        let api = FakeAPI()
        let seasons = [
            LibraryEntry(item: MediaItem(id: "se1", name: "Saison 1", kind: .season, seriesId: "s1", indexNumber: 1)),
            LibraryEntry(item: MediaItem(id: "se2", name: "Saison 2", kind: .season, seriesId: "s1", indexNumber: 2)),
        ]
        await api.setSeasons(seasons, of: "s1")
        await api.setEpisodes([episode("e1", season: "se1", number: 1), episode("e2", season: "se1", number: 2, position: 500), episode("e3", season: "se2", number: 1)], of: "s1")
        let store = makeStore(api)
        try await store.ensureSeriesFresh("s1")
        #expect(store.seasons(of: "s1").map(\.id) == ["se1", "se2"])
        let episodes = store.episodes(of: "s1")
        #expect(episodes.map(\.item.id) == ["e1", "e2", "e3"])
        #expect(episodes[1].userData.progress(runtimeTicks: episodes[1].item.runtimeTicks) == 0.5)
        try await store.ensureSeriesFresh("s1")
        #expect(await api.callCount("seasons:s1") == 1)
        #expect(await api.callCount("episodes:s1") == 1)
    }

    @Test func detailAndChildrenSurviveAShelfReloadOfTheSameItem() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        await api.setLatest([LibraryEntry(item: MediaItem(id: "m1", name: "Nocturne"))], in: "films")
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        try await store.ensureFresh(.latestIn(libraryId: "films"))
        #expect(store.detail("m1")?.overview == "Une nuit.")
    }

    // MARK: Favorite

    @Test func favoriteIsPatchedAtOnceAndSentToTheServer() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        try await store.setFavorite(true, for: "m1")
        #expect(store.userData["m1"]?.isFavorite == true)
        #expect(await api.favoriteCalls == ["m1:true"])
        try await store.setFavorite(false, for: "m1")
        #expect(store.userData["m1"]?.isFavorite == false)
    }

    @Test func favoriteRollsBackWhenTheServerRefuses() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        await api.queueErrors([Boom()])
        await #expect(throws: Boom.self) { try await store.setFavorite(true, for: "m1") }
        #expect(store.userData["m1"]?.isFavorite == false)
    }

    @Test func favoriteIsVisibleBeforeTheServerAnswers() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        await api.holdAnswers()
        let task = Task { try await store.setFavorite(true, for: "m1") }
        await api.waitUntilParked()
        #expect(store.userData["m1"]?.isFavorite == true)
        await api.releaseAnswers()
        try await task.value
    }

    @Test func favoriteCancelsADetailLoadInFlightSoItsStaleAnswerCannotUndoIt() async throws {
        let api = FakeAPI()
        await api.setDetail(movie())
        let store = makeStore(api)
        await api.holdAnswers()
        let load = Task { try await store.ensureDetailFresh("m1") }
        await api.waitUntilParked()
        // The parked call is the detail load; patching now must discard its answer.
        let favorite = Task { try await store.setFavorite(true, for: "m1") }
        await api.releaseAnswers()
        try await load.value
        try await favorite.value
        #expect(store.userData["m1"]?.isFavorite == true)
    }

    // MARK: Watched

    private func played(_ value: Bool) -> UserData {
        UserData(played: value, playbackPositionTicks: value ? 0 : 40, playCount: value ? 1 : 0, isFavorite: false, lastPlayedDate: nil)
    }

    @Test func playedIsPatchedAtOnceResetsTheResumePositionAndIsSentToTheServer() async throws {
        let api = FakeAPI()
        await api.setDetail(movie(), userData: played(false))
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        try await store.setPlayed(true, for: "m1")
        #expect(store.userData["m1"]?.played == true)
        #expect(store.userData["m1"]?.playbackPositionTicks == 0)
        #expect(await api.playedCalls == ["m1:true"])
        try await store.setPlayed(false, for: "m1")
        #expect(store.userData["m1"]?.played == false)
    }

    @Test func playedRollsBackWhenTheServerRefuses() async throws {
        let api = FakeAPI()
        await api.setDetail(movie(), userData: played(false))
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        await api.queueErrors([Boom()])
        await #expect(throws: Boom.self) { try await store.setPlayed(true, for: "m1") }
        #expect(store.userData["m1"]?.played == false)
        #expect(store.userData["m1"]?.playbackPositionTicks == 40)
    }

    @Test func playedIsVisibleBeforeTheServerAnswers() async throws {
        let api = FakeAPI()
        await api.setDetail(movie(), userData: played(false))
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        await api.holdAnswers()
        let task = Task { try await store.setPlayed(true, for: "m1") }
        await api.waitUntilParked()
        #expect(store.userData["m1"]?.played == true)
        await api.releaseAnswers()
        try await task.value
    }

    @Test func playedInvalidatesContinueWatchingAndNextUpOnSuccessOnly() async throws {
        let api = FakeAPI()
        await api.setDetail(movie(), userData: played(false))
        await api.setResume([entry("m1")])
        let store = makeStore(api)
        try await store.ensureDetailFresh("m1")
        try await store.ensureFresh(.continueWatching)
        try await store.ensureFresh(.nextUp)
        #expect(!store.isStale(.continueWatching) && !store.isStale(.nextUp))

        await api.queueErrors([Boom()])
        await #expect(throws: Boom.self) { try await store.setPlayed(true, for: "m1") }
        #expect(!store.isStale(.continueWatching) && !store.isStale(.nextUp))

        try await store.setPlayed(true, for: "m1")
        #expect(store.isStale(.continueWatching) && store.isStale(.nextUp))
    }

    @Test func playedOnAnEpisodeUpdatesTheSeriesEpisodeList() async throws {
        let api = FakeAPI()
        await api.setSeasons([LibraryEntry(item: MediaItem(id: "se1", name: "S1", kind: .season, seriesId: "s1", indexNumber: 1))], of: "s1")
        await api.setEpisodes([episode("e1", season: "se1", number: 1, position: 500)], of: "s1")
        let store = makeStore(api)
        try await store.ensureSeriesFresh("s1")
        try await store.setPlayed(true, for: "e1")
        #expect(store.episodes(of: "s1").first?.userData.played == true)
    }
}

@Suite struct ChapterMappingTests {
    @Test func chaptersConvertTicksToSecondsAndSort() throws {
        let dto = BaseItemDto(
            chapters: [
                ChapterInfo(name: "Fin", startPositionTicks: 36_000_000_000),
                ChapterInfo(name: "Début", startPositionTicks: 0),
                ChapterInfo(name: "Sans temps"),
            ],
            id: "m1", name: "M", type: .movie
        )
        let detail = try #require(ItemDetail(dto: dto))
        #expect(detail.chapters == [Chapter(name: "Début", startSeconds: 0), Chapter(name: "Fin", startSeconds: 3600)])
    }

    @Test func noChaptersIsEmpty() throws {
        let detail = try #require(ItemDetail(dto: BaseItemDto(id: "m1", name: "M", type: .movie)))
        #expect(detail.chapters.isEmpty)
    }
}
