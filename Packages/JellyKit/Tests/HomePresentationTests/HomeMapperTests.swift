import DesignSystem
import Foundation
import LibraryKit
import Testing
@testable import HomePresentation

private let minute: Int64 = 600_000_000

private func entry(
    _ id: String, _ name: String, series: String? = nil, tag: String? = "t", runtimeMinutes: Int64 = 100,
    positionMinutes: Int64 = 0, played: Bool = false
) -> LibraryEntry {
    LibraryEntry(
        item: MediaItem(id: id, name: name, seriesName: series, primaryImageTag: tag, runtimeTicks: runtimeMinutes * minute),
        userData: UserData(played: played, playbackPositionTicks: positionMinutes * minute, playCount: 0, isFavorite: false, lastPlayedDate: nil)
    )
}

private let urls: HomeMapper.ImageURL = { id, kind, tag, width in
    tag.flatMap { URL(string: "https://jf.test/\(id)/\(kind == .logo ? "logo/" : "")\($0)/\(width)") }
}

private func films(_ entries: [LibraryEntry]) -> LibraryShelfSource {
    LibraryShelfSource(library: Library(id: "films", name: "Films", kind: .movies), entries: entries)
}

@Suite struct HomeMapperTests {
    @Test func oneShelfPerLibraryInServerOrderWithTheLibraryNameInTheTitle() {
        let series = LibraryShelfSource(library: Library(id: "series", name: "Séries", kind: .tvshows), entries: [entry("s1", "Ep", series: "Nocturne")])
        let content = HomeMapper.content(continueWatching: [], nextUp: [], libraries: [films([entry("r1", "Neuf")]), series], imageURL: urls)
        #expect(content.libraryShelves.map(\.id) == ["films", "series"])
        #expect(content.libraryShelves.map(\.title) == ["Films — Ajouts récents", "Séries — Ajouts récents"])
        #expect(content.libraryShelves[1].items.map(\.id) == ["s1"])
    }

    @Test func libraryWithoutEntriesKeepsItsShelfButContentIsEmpty() {
        let content = HomeMapper.content(continueWatching: [], nextUp: [], libraries: [films([])], imageURL: urls)
        #expect(content.libraryShelves.count == 1)
        #expect(content.isEmpty)
    }

    @Test func gridKeepsOrder() {
        let library = Library(id: "films", name: "Films", kind: .movies)
        let grid = HomeMapper.grid(library: library, entries: [entry("b", "B"), entry("a", "A")], imageURL: urls)
        #expect(grid.title == "Films")
        #expect(grid.items.map(\.id) == ["b", "a"])
    }

    @Test func upNextPutsResumesFirstAndDedupesByIdAndSeries() {
        let resume = [entry("e2", "Pilot 2", series: "Nocturne", positionMinutes: 10), entry("m1", "Cendres", positionMinutes: 5)]
        let next = [entry("e2", "Pilot 2", series: "Nocturne"), entry("e3", "Pilot 3", series: "Nocturne"), entry("f1", "Un", series: "Fréquences")]
        let ids = HomeMapper.upNextEntries(continueWatching: resume, nextUp: next).map(\.item.id)
        #expect(ids == ["e2", "m1", "f1"])
    }

    @Test func billboardIsFirstUpNextElseFirstRecent() {
        let withResume = HomeMapper.content(
            continueWatching: [entry("m1", "Cendres", positionMinutes: 30)], nextUp: [], libraries: [films([entry("r1", "Neuf")])], imageURL: urls
        )
        #expect(withResume.billboard?.model.id == "m1")
        #expect(withResume.billboard?.target.resumeSeconds == 1800)
        #expect(withResume.billboard?.primaryLabel == String(localized: "Reprendre"))

        let recentOnly = HomeMapper.content(continueWatching: [], nextUp: [], libraries: [films([entry("r1", "Neuf")])], imageURL: urls)
        #expect(recentOnly.billboard?.model.id == "r1")
        #expect(recentOnly.billboard?.target.resumeSeconds == 0)
        #expect(recentOnly.billboard?.primaryLabel == String(localized: "Lecture"))
    }

    @Test func emptyInputIsEmptyContent() {
        let content = HomeMapper.content(continueWatching: [], nextUp: [], libraries: [], imageURL: urls)
        #expect(content.isEmpty)
        #expect(content.billboard == nil)
    }

    @Test func landscapeCarriesProgressAndEpisodeSubtitle() throws {
        let model = HomeMapper.landscape(entry("e1", "Épisode 3", series: "Nocturne", runtimeMinutes: 50, positionMinutes: 20), imageURL: urls)
        #expect(model.title == "Nocturne")
        #expect(model.subtitle?.hasPrefix("Épisode 3") == true)
        #expect(try #require(model.progress) == 0.4)
        #expect(model.image.url?.absoluteString == "https://jf.test/e1/t/\(HomeMapper.landscapeImageWidth)")
    }

    @Test func movieLandscapeShowsOnlyRemaining() {
        let model = HomeMapper.landscape(entry("m1", "Cendres", runtimeMinutes: 100, positionMinutes: 46), imageURL: urls)
        #expect(model.title == "Cendres")
        #expect(model.subtitle == MediaFormat.remaining(seconds: 54 * 60))
    }

    @Test func missingImageTagKeepsPlaceholderTitle() {
        let model = HomeMapper.poster(entry("m1", "Cendres", tag: nil), imageURL: urls)
        #expect(model.image.url == nil)
        #expect(model.image.placeholderTitle == "Cendres")
    }

    @Test func watchedItemResumesFromStart() {
        let target = HomeMapper.target(for: entry("m1", "Cendres", positionMinutes: 90, played: true))
        #expect(target.resumeSeconds == 0)
    }

    @Test func targetsCoverEveryShelf() {
        let content = HomeMapper.content(continueWatching: [entry("a", "A")], nextUp: [], libraries: [films([entry("b", "B")])], imageURL: urls)
        #expect(content.target(for: "a")?.id == "a")
        #expect(content.target(for: "b")?.title == "B")
        #expect(content.target(for: "zz") == nil)
    }

    // MARK: Billboard « Ma liste »

    @Test func billboardListStateFollowsTheItemItself() {
        let content = HomeMapper.content(
            continueWatching: [], nextUp: [], libraries: [films([entry("r1", "Neuf")])], isInList: { $0 == "r1" }, imageURL: urls
        )
        #expect(content.billboard?.model.isInList == true)
        #expect(content.billboard?.listId == "r1")
        let other = HomeMapper.content(continueWatching: [], nextUp: [], libraries: [films([entry("r1", "Neuf")])], imageURL: urls)
        #expect(other.billboard?.model.isInList == false)
    }

    @Test func billboardOfAnEpisodeActsOnItsSeries() {
        let episode = LibraryEntry(item: MediaItem(id: "e1", name: "Ep", seriesName: "Nocturne", runtimeTicks: 40 * minute, kind: .episode, seriesId: "s1"))
        let content = HomeMapper.content(
            continueWatching: [episode], nextUp: [], libraries: [], isInList: { $0 == "s1" }, imageURL: urls
        )
        #expect(content.billboard?.listId == "s1")
        #expect(content.billboard?.model.isInList == true)
        // The episode's own flag is irrelevant.
        let own = HomeMapper.content(continueWatching: [episode], nextUp: [], libraries: [], isInList: { $0 == "e1" }, imageURL: urls)
        #expect(own.billboard?.model.isInList == false)
    }

    @Test func billboardCarriesTheItemsOwnLogoAtDetailWidth() {
        let movie = LibraryEntry(item: MediaItem(id: "m1", name: "Neuf", primaryImageTag: "p", kind: .movie, logoImageTag: "lg"))
        let content = HomeMapper.content(continueWatching: [movie], nextUp: [], libraries: [], imageURL: urls)
        #expect(content.billboard?.model.logo == URL(string: "https://jf.test/m1/logo/lg/\(DetailMapper.logoImageWidth)"))
    }

    @Test func billboardOfAnEpisodeUsesTheSeriesLogo() {
        let episode = LibraryEntry(item: MediaItem(
            id: "e1", name: "Ep", seriesName: "Nocturne", primaryImageTag: "p", kind: .episode, seriesId: "s1",
            logoImageTag: "lg", logoItemId: "s1"
        ))
        let content = HomeMapper.content(continueWatching: [episode], nextUp: [], libraries: [], imageURL: urls)
        #expect(content.billboard?.model.logo == URL(string: "https://jf.test/s1/logo/lg/\(DetailMapper.logoImageWidth)"))
    }

    @Test func billboardWithoutLogoFallsBackToText() {
        let content = HomeMapper.content(continueWatching: [entry("m1", "Neuf")], nextUp: [], libraries: [], imageURL: urls)
        #expect(content.billboard?.model.logo == nil)
    }

    @Test func billboardOfAnEpisodeOfAnUnknownSeriesActsOnTheEpisode() {
        let episode = LibraryEntry(item: MediaItem(id: "e1", name: "Ep", seriesName: "Nocturne", kind: .episode))
        let content = HomeMapper.content(continueWatching: [episode], nextUp: [], libraries: [], isInList: { $0 == "e1" }, imageURL: urls)
        #expect(content.billboard?.listId == "e1")
        #expect(content.billboard?.model.isInList == true)
    }
}
