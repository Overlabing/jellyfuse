import DesignSystem
import Foundation
import LibraryKit

/// The grouped results of one search, as display values (ui-plan §6.6): Films, Séries, then Épisodes.
public struct SearchContent: Sendable, Equatable {
    public let movies: [PosterModel]
    public let series: [PosterModel]
    public let episodes: [LandscapeModel]
    /// Episode id -> the series whose detail screen it opens (an episode has none of its own).
    private let episodeSeries: [String: String]

    public static let empty = SearchContent(movies: [], series: [], episodes: [], episodeSeries: [:])

    public var isEmpty: Bool { movies.isEmpty && series.isEmpty && episodes.isEmpty }

    init(movies: [PosterModel], series: [PosterModel], episodes: [LandscapeModel], episodeSeries: [String: String]) {
        self.movies = movies
        self.series = series
        self.episodes = episodes
        self.episodeSeries = episodeSeries
    }

    /// The detail screen to open for a card: the item itself, or the series for an episode.
    public func detailId(for id: String) -> String { episodeSeries[id] ?? id }
}

/// Pure mapping from search results to display models. Reuses the home cards' mapping.
public enum SearchMapper {
    public static func content(
        movies: [LibraryEntry], series: [LibraryEntry], episodes: [LibraryEntry], imageURL: HomeMapper.ImageURL
    ) -> SearchContent {
        var episodeSeries: [String: String] = [:]
        for entry in episodes {
            if let seriesId = entry.item.seriesId { episodeSeries[entry.item.id] = seriesId }
        }
        return SearchContent(
            movies: movies.map { HomeMapper.poster($0, imageURL: imageURL) },
            series: series.map { HomeMapper.poster($0, imageURL: imageURL) },
            // An episode of an unknown series has nowhere to go: it is left out.
            episodes: episodes.filter { $0.item.seriesId != nil }.map { HomeMapper.landscape($0, imageURL: imageURL) },
            episodeSeries: episodeSeries
        )
    }
}
