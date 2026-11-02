import DesignSystem
import Foundation
import LibraryKit
import Testing
@testable import HomePresentation

private func entry(_ id: String, _ name: String, kind: MediaItem.Kind, series: String? = nil, seriesId: String? = nil) -> LibraryEntry {
    LibraryEntry(item: MediaItem(id: id, name: name, seriesName: series, primaryImageTag: "t", kind: kind, seriesId: seriesId))
}

private let urls: HomeMapper.ImageURL = { id, _, tag, width in
    tag.flatMap { URL(string: "https://jf.test/\(id)/\($0)/\(width)") }
}

@Suite struct SearchMapperTests {
    @Test func groupsByKindAndRoutesEpisodesToTheirSeries() {
        let content = SearchMapper.content(
            movies: [entry("m1", "Nocturne", kind: .movie)],
            series: [entry("s1", "Nocturne", kind: .series)],
            episodes: [entry("e1", "Pilote", kind: .episode, series: "Nocturne", seriesId: "s1")],
            imageURL: urls
        )
        #expect(content.movies.map(\.id) == ["m1"])
        #expect(content.series.map(\.id) == ["s1"])
        #expect(content.episodes.map(\.id) == ["e1"])
        #expect(content.episodes.first?.title == "Nocturne")
        #expect(content.detailId(for: "e1") == "s1")
        #expect(content.detailId(for: "m1") == "m1")
        #expect(!content.isEmpty)
    }

    @Test func episodeWithoutSeriesIsDropped() {
        let content = SearchMapper.content(movies: [], series: [], episodes: [entry("e1", "Orphelin", kind: .episode)], imageURL: urls)
        #expect(content.isEmpty)
    }
}

@Suite struct SearchQueryTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(SearchQuery("  la   nuit ")?.term == "la nuit")
    }

    @Test func belowTwoCharactersIsNotSearched() {
        #expect(SearchQuery("a") == nil)
        #expect(SearchQuery("   ") == nil)
        #expect(SearchQuery(" a ") == nil)
        #expect(SearchQuery("ab") != nil)
    }
}

private actor FakeSearchAPI: SearchAPI {
    struct Call: Equatable { let term: String; let kind: SearchKind; let limit: Int }
    private(set) var calls: [Call] = []
    private var failuresLeft: Int
    private let delays: [String: Duration]

    init(failures: Int = 0, delays: [String: Duration] = [:]) {
        failuresLeft = failures
        self.delays = delays
    }

    func search(_ query: SearchQuery, kind: SearchKind, limit: Int) async throws -> [LibraryEntry] {
        calls.append(Call(term: query.term, kind: kind, limit: limit))
        if let delay = delays[query.term] { try await Task.sleep(for: delay) }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw JellyfinError.badResponse
        }
        guard query.term != "rien" else { return [] }
        switch kind {
        case .movie: return [entry("m-\(query.term)", query.term, kind: .movie)]
        case .series: return [entry("s-\(query.term)", query.term, kind: .series)]
        case .episode: return [entry("e-\(query.term)", "Ep", kind: .episode, series: query.term, seriesId: "s-\(query.term)")]
        }
    }
}

@MainActor
private final class Ingested {
    var ids: [String] = []
}

@MainActor
@Suite struct SearchModelTests {
    private func model(_ api: FakeSearchAPI, _ sink: Ingested = Ingested()) -> SearchModel {
        SearchModel(
            api: api, ingest: { sink.ids += $0.map(\.item.id) }, imageURL: urls,
            debounce: .milliseconds(30), retryDelay: .milliseconds(5)
        )
    }

    @Test func queryAskesEveryKindWithTheLimitAndFeedsTheStore() async {
        let api = FakeSearchAPI()
        let sink = Ingested()
        let model = model(api, sink)
        model.query = "nuit"
        #expect(model.phase == .loading)
        await model.settled()
        #expect(model.phase == .results)
        let calls = await api.calls
        #expect(Set(calls.map(\.kind)) == Set(SearchKind.allCases))
        #expect(calls.allSatisfy { $0.term == "nuit" && $0.limit == SearchQuery.limitPerKind })
        #expect(Set(sink.ids) == ["m-nuit", "s-nuit", "e-nuit"])
        #expect(model.content.movies.map(\.id) == ["m-nuit"])
    }

    @Test func typingWithinTheDebounceSendsOneRequestForTheLastTerm() async throws {
        let api = FakeSearchAPI()
        let model = model(api)
        model.query = "nu"
        model.query = "nui"
        model.query = "nuit"
        await model.settled()
        let terms = Set(await api.calls.map(\.term))
        #expect(terms == ["nuit"])
    }

    @Test func aNewQueryDropsTheAnswerOfTheOneInFlight() async throws {
        let api = FakeSearchAPI(delays: ["lent": .milliseconds(200)])
        let model = model(api)
        model.query = "lent"
        try await Task.sleep(for: .milliseconds(80))  // past the debounce: "lent" is in flight
        model.query = "vite"
        await model.settled()
        #expect(model.phase == .results)
        #expect(model.content.movies.map(\.id) == ["m-vite"])
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.content.movies.map(\.id) == ["m-vite"])
    }

    @Test func shortQueryReturnsToIdleAndClearsResults() async {
        let model = model(FakeSearchAPI())
        model.query = "nuit"
        await model.settled()
        model.query = "n"
        #expect(model.phase == .idle)
        #expect(model.content.isEmpty)
    }

    @Test func noMatchIsAnEmptyPhaseNamingTheTerm() async {
        let model = model(FakeSearchAPI())
        model.query = "rien"
        await model.settled()
        #expect(model.phase == .empty(term: "rien"))
    }

    @Test func oneFailureIsRetriedSilently() async {
        let model = model(FakeSearchAPI(failures: 1))
        model.query = "nuit"
        await model.settled()
        #expect(model.phase == .results)
    }

    @Test func persistentFailureSurfacesAndRetryRecovers() async {
        let api = FakeSearchAPI(failures: 6)
        let model = model(api)
        model.query = "nuit"
        await model.settled()
        #expect(model.phase == .failed(term: "nuit"))
        model.retry()
        await model.settled()
        #expect(model.phase == .results)
    }
}
