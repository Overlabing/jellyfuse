import DesignSystem
import Foundation
import LibraryKit
import Testing
@testable import HomePresentation

private let minute: Int64 = 600_000_000

private let urls: DetailMapper.ImageURL = { id, kind, tag, width in
    tag.flatMap { URL(string: "https://jf.test/\(id)/\(kind)/\($0)/\(width)") }
}

private func episode(
    _ id: String, season: String, number: Int, seasonNumber: Int = 1, positionMinutes: Int64 = 0, played: Bool = false, lastPlayed: TimeInterval? = nil
) -> LibraryEntry {
    LibraryEntry(
        item: MediaItem(
            id: id, name: "Ep \(number)", primaryImageTag: "t", runtimeTicks: 40 * minute, kind: .episode,
            seriesId: "s1", seasonId: season, indexNumber: number, parentIndexNumber: seasonNumber
        ),
        userData: UserData(
            played: played, playbackPositionTicks: positionMinutes * minute, playCount: played ? 1 : 0, isFavorite: false,
            lastPlayedDate: lastPlayed.map { Date(timeIntervalSince1970: $0) }
        )
    )
}

private let seasons = [
    MediaItem(id: "se1", name: "Saison 1", kind: .season, seriesId: "s1", indexNumber: 1),
    MediaItem(id: "se2", name: "Saison 2", kind: .season, seriesId: "s1", indexNumber: 2),
]

private let series = MediaItem(id: "s1", name: "Fréquences", kind: .series)

private func seriesContent(_ episodes: [LibraryEntry], selected: String? = nil) -> DetailContent {
    DetailMapper.content(item: series, detail: nil, userData: .none, seasons: seasons, episodes: episodes, selectedSeasonId: selected, imageURL: urls)
}

@Suite struct DetailMapperTests {
    @Test func movieHeaderCarriesLogoBackdropAndMeta() {
        let item = MediaItem(id: "m1", name: "Nocturne", runtimeTicks: 128 * minute, kind: .movie)
        let detail = ItemDetail(
            item: item, overview: "Une nuit.", productionYear: 2025, communityRating: 7.8, officialRating: "TP",
            genres: ["Drame", "Thriller", "Policier", "Autre"], backdropImageTag: "bd", logoImageTag: "lg"
        )
        let content = DetailMapper.content(item: item, detail: detail, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(content.header.logo?.absoluteString == "https://jf.test/m1/logo/lg/800")
        #expect(content.header.backdrop.url?.absoluteString == "https://jf.test/m1/backdrop/bd/1920")
        #expect(content.header.overview == "Une nuit.")
        #expect(!content.isSeries)
        #expect(content.seasons.isEmpty)
        let parts = content.header.metaParts(locale: Locale(identifier: "en_US"))
        #expect(parts == [.rating("★ 7.8"), .text("TP"), .text("2025"), .text("2 h 08"), .text("Drame, Thriller, Policier")])
    }

    @Test func missingLogoFallsBackToTextTitle() {
        let item = MediaItem(id: "m1", name: "Nocturne", kind: .movie)
        let detail = ItemDetail(item: item, backdropImageTag: "bd")
        let content = DetailMapper.content(item: item, detail: detail, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(content.header.logo == nil)
        #expect(content.header.title == "Nocturne")
    }

    @Test func headerIsUsableBeforeTheDetailAnswers() {
        let item = MediaItem(id: "m1", name: "Nocturne", kind: .movie)
        let content = DetailMapper.content(item: item, detail: nil, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(content.header.title == "Nocturne")
        #expect(content.header.logo == nil)
        #expect(content.header.overview.isEmpty)
    }

    @Test func movieLabelAndTargetFollowTheResumePosition() {
        let item = MediaItem(id: "m1", name: "Nocturne", runtimeTicks: 100 * minute, kind: .movie)
        let fresh = DetailMapper.content(item: item, detail: nil, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(fresh.playLabel == "Lecture")
        #expect(fresh.playTarget?.resumeSeconds == 0)
        let started = UserData(played: false, playbackPositionTicks: 30 * minute, playCount: 0, isFavorite: true, lastPlayedDate: nil)
        let resumed = DetailMapper.content(item: item, detail: nil, userData: started, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(resumed.playLabel == "Reprendre")
        #expect(resumed.playTarget?.resumeSeconds == 1800)
        #expect(resumed.isFavorite)
    }

    @Test func yearRangeShownOnlyForEndedSeriesWithADifferentLastYear() {
        #expect(DetailMapper.yearText(start: 2022, end: 2025) == "2022 – 2025")
        #expect(DetailMapper.yearText(start: 2022, end: 2022) == "2022")
        #expect(DetailMapper.yearText(start: 2022, end: nil) == "2022")
        #expect(DetailMapper.yearText(start: nil, end: 2025) == nil)
    }

    // MARK: Series

    @Test func freshSeriesPlaysTheFirstEpisode() {
        let content = seriesContent([episode("e1", season: "se1", number: 1), episode("e2", season: "se1", number: 2)])
        #expect(content.isSeries)
        #expect(content.playTarget?.id == "e1")
        #expect(content.playLabel == "Lecture S1 · E1")
        #expect(content.header.metaParts().contains(.text("2 saisons")))
    }

    @Test func inProgressEpisodeWinsAndLabelsResume() {
        let content = seriesContent([
            episode("e1", season: "se1", number: 1, played: true, lastPlayed: 100),
            episode("e2", season: "se1", number: 2, positionMinutes: 10, lastPlayed: 200),
            episode("e3", season: "se1", number: 3),
        ])
        #expect(content.playTarget?.id == "e2")
        #expect(content.playTarget?.resumeSeconds == 600)
        #expect(content.playLabel == "Reprendre S1 · E2")
    }

    @Test func nextEpisodeAfterTheLastWatchedOneIsPlayed() {
        let content = seriesContent([
            episode("e1", season: "se1", number: 1, played: true, lastPlayed: 100),
            episode("e2", season: "se1", number: 2, played: true, lastPlayed: 300),
            episode("e3", season: "se2", number: 1, seasonNumber: 2),
        ])
        #expect(content.playTarget?.id == "e3")
        #expect(content.playLabel == "Lecture S2 · E1")
        #expect(content.selectedSeasonId == "se2")
    }

    @Test func fullyWatchedSeriesStartsOver() {
        let entries = [
            episode("e1", season: "se1", number: 1, played: true, lastPlayed: 100),
            episode("e2", season: "se1", number: 2, played: true, lastPlayed: 200),
        ]
        #expect(DetailMapper.seriesPlayEntry(episodes: entries)?.item.id == "e1")
    }

    @Test func seriesWithoutEpisodesHasNoTarget() {
        let content = seriesContent([])
        #expect(content.playTarget == nil)
        #expect(content.playLabel == "Lecture")
        #expect(content.selectedSeasonId == "se1")
    }

    @Test func seasonSelectionFiltersEpisodesAndUnknownSelectionFallsBack() {
        let all = [
            episode("e1", season: "se1", number: 1),
            episode("e2", season: "se2", number: 1, seasonNumber: 2),
            episode("e3", season: "se2", number: 2, seasonNumber: 2),
        ]
        let second = seriesContent(all, selected: "se2")
        #expect(second.seasons.map(\.title) == ["Saison 1", "Saison 2"])
        #expect(second.episodes.map(\.id) == ["e2", "e3"])
        #expect(second.target(forEpisode: "e3")?.id == "e3")
        #expect(second.target(forEpisode: "e1") == nil)
        #expect(seriesContent(all, selected: "gone").selectedSeasonId == "se1")
    }

    @Test func episodeCardsCarryNumberRuntimeProgressAndWatchedFlag() {
        let content = seriesContent([
            episode("e1", season: "se1", number: 1, played: true),
            episode("e2", season: "se1", number: 2, positionMinutes: 20),
        ], selected: "se1")
        let (watched, partial) = (content.episodes[0], content.episodes[1])
        #expect(watched.title == "1. Ep 1")
        #expect(watched.subtitle == "40 min")
        #expect(watched.isWatched)
        #expect(partial.progress == 0.5)
        #expect(partial.subtitle == "20 min restantes")
        #expect(!partial.isWatched)
    }

    // MARK: Cast and watched

    private func person(_ id: String, _ kind: Person.Kind, role: String? = nil, tag: String? = nil) -> Person {
        Person(id: id, name: "Name \(id)", kind: kind, role: role, primaryImageTag: tag)
    }

    @Test func peopleListDirectorsFirstWithRoleAndPortrait() {
        let models = DetailMapper.people(
            [person("a1", .actor, role: "Léa", tag: "t1"), person("a2", .actor), person("d1", .director)], imageURL: urls
        )
        #expect(models.map(\.name) == ["Name d1", "Name a1", "Name a2"])
        #expect(models[0].role == String(localized: "Réalisation"))
        #expect(models[1].role == "Léa")
        #expect(models[2].role == nil)
        #expect(models[1].image.url?.absoluteString == "https://jf.test/a1/primary/t1/300")
        #expect(models[2].image.url == nil)
        #expect(models[2].image.placeholderTitle == "Name a2")
    }

    @Test func peopleAreCappedAndDeduplicated() {
        let actors = (0..<30).map { person("a\($0)", .actor) }
        let models = DetailMapper.people(actors + [person("a0", .actor), person("a0", .director)], imageURL: urls)
        #expect(models.count == DetailMapper.peopleLimit)
        #expect(Set(models.map(\.id)).count == models.count)
        // The same person credited as director and actor keeps both cards, with distinct ids.
        let both = DetailMapper.people([person("x", .actor), person("x", .director)], imageURL: urls)
        #expect(both.count == 2 && both[0].id != both[1].id)
    }

    @Test func contentCarriesPeopleForMovieAndSeries() {
        let item = MediaItem(id: "m1", name: "Nocturne", kind: .movie)
        let detail = ItemDetail(item: item, people: [person("a1", .actor)])
        let movie = DetailMapper.content(item: item, detail: detail, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(movie.people.count == 1)
        let withoutDetail = DetailMapper.content(item: item, detail: nil, userData: .none, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(withoutDetail.people.isEmpty)
        let show = DetailMapper.content(
            item: series, detail: ItemDetail(item: series, people: [person("a1", .actor)]), userData: .none,
            seasons: seasons, episodes: [], selectedSeasonId: nil, imageURL: urls
        )
        #expect(show.people.count == 1)
    }

    @Test func watchedStateIsForMoviesOnly() {
        let item = MediaItem(id: "m1", name: "Nocturne", kind: .movie)
        let watched = UserData(played: true, playbackPositionTicks: 0, playCount: 1, isFavorite: false, lastPlayedDate: nil)
        let movie = DetailMapper.content(item: item, detail: nil, userData: watched, seasons: [], episodes: [], selectedSeasonId: nil, imageURL: urls)
        #expect(movie.isWatched == true)
        #expect(seriesContent([episode("e1", season: "se1", number: 1)]).isWatched == nil)
    }
}
