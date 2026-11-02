import DesignSystem
import Foundation
import LibraryKit

/// A season selector chip.
public struct SeasonChip: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
}

/// Everything the detail screen shows, as display values.
public struct DetailContent: Sendable, Equatable {
    public let header: DetailHeaderModel
    /// A series shows its seasons and episodes under the header; a movie's header fills the screen.
    public let isSeries: Bool
    /// What the Lecture button plays; nil while nothing is playable (series without episodes).
    public let playTarget: PlayTarget?
    /// `Lecture`, `Reprendre`, `Reprendre S2 · E5`.
    public let playLabel: String
    public let isFavorite: Bool
    /// Empty for a movie.
    public let seasons: [SeasonChip]
    public let selectedSeasonId: String?
    /// The episodes of the selected season.
    public let episodes: [LandscapeModel]
    private let episodeTargets: [String: PlayTarget]

    init(
        header: DetailHeaderModel, isSeries: Bool, playTarget: PlayTarget?, playLabel: String, isFavorite: Bool,
        seasons: [SeasonChip], selectedSeasonId: String?, episodes: [LandscapeModel], episodeTargets: [String: PlayTarget]
    ) {
        self.header = header
        self.isSeries = isSeries
        self.playTarget = playTarget
        self.playLabel = playLabel
        self.isFavorite = isFavorite
        self.seasons = seasons
        self.selectedSeasonId = selectedSeasonId
        self.episodes = episodes
        self.episodeTargets = episodeTargets
    }

    public func target(forEpisode id: String) -> PlayTarget? { episodeTargets[id] }
}

/// Pure mapping from the store's detail data to the detail screen's display values.
public enum DetailMapper {
    /// `(itemId, image kind, tag, maxWidth)` -> image URL; the app passes `JellyfinClient.imageURL`.
    public typealias ImageURL = @Sendable (_ itemId: String, _ kind: ItemImageKind, _ tag: String?, _ maxWidth: Int) -> URL?

    public static let backdropImageWidth = 1920
    public static let logoImageWidth = 800
    public static let episodeImageWidth = HomeMapper.landscapeImageWidth

    /// - Parameters:
    ///   - item: the item as the shelves know it, shown while `detail` has not answered yet.
    ///   - seasons / episodes: a series' children; ignored for a movie.
    ///   - selectedSeasonId: the chip chosen by the user; nil or unknown selects the season of the play target.
    public static func content(
        item: MediaItem,
        detail: ItemDetail?,
        userData: UserData,
        seasons: [MediaItem],
        episodes: [LibraryEntry],
        selectedSeasonId: String?,
        imageURL: ImageURL
    ) -> DetailContent {
        let isSeries = item.kind == .series
        let resumeEntry = isSeries ? seriesPlayEntry(episodes: episodes) : LibraryEntry(item: item, userData: userData)
        let selected = isSeries ? resolvedSeasonId(selectedSeasonId, seasons: seasons, playEntry: resumeEntry) : nil
        let seasonEpisodes = episodes.filter { $0.item.seasonId == selected }

        return DetailContent(
            header: header(item: item, detail: detail, seasonCount: isSeries ? seasons.count : nil, imageURL: imageURL),
            isSeries: isSeries,
            playTarget: resumeEntry.map(HomeMapper.target(for:)),
            playLabel: playLabel(isSeries: isSeries, entry: resumeEntry, episodes: episodes),
            isFavorite: userData.isFavorite,
            seasons: isSeries ? seasons.map { SeasonChip(id: $0.id, title: $0.name) } : [],
            selectedSeasonId: selected,
            episodes: seasonEpisodes.map { episode($0, imageURL: imageURL) },
            episodeTargets: Dictionary(
                seasonEpisodes.map { ($0.item.id, HomeMapper.target(for: $0)) }, uniquingKeysWith: { first, _ in first }
            )
        )
    }

    // MARK: Series play target

    /// The episode the series' Lecture button plays: the one in progress (most recent), else the one
    /// after the last watched, else the first. A fully watched series starts over.
    public static func seriesPlayEntry(episodes: [LibraryEntry]) -> LibraryEntry? {
        let inProgress = episodes.enumerated().filter { !$0.element.userData.played && $0.element.userData.playbackPositionTicks > 0 }
        if let latest = inProgress.max(by: { isBefore($0, $1) }) { return latest.element }
        let played = episodes.enumerated().filter { $0.element.userData.played }
        guard let last = played.max(by: { isBefore($0, $1) }) else { return episodes.first }
        return last.offset + 1 < episodes.count ? episodes[last.offset + 1] : episodes.first
    }

    /// Orders by last played date, then by position in the list (a missing date sorts first).
    private static func isBefore(_ a: (offset: Int, element: LibraryEntry), _ b: (offset: Int, element: LibraryEntry)) -> Bool {
        let (dateA, dateB) = (a.element.userData.lastPlayedDate ?? .distantPast, b.element.userData.lastPlayedDate ?? .distantPast)
        return dateA == dateB ? a.offset < b.offset : dateA < dateB
    }

    private static func resolvedSeasonId(_ selected: String?, seasons: [MediaItem], playEntry: LibraryEntry?) -> String? {
        if let selected, seasons.contains(where: { $0.id == selected }) { return selected }
        if let seasonId = playEntry?.item.seasonId, seasons.contains(where: { $0.id == seasonId }) { return seasonId }
        return seasons.first?.id
    }

    private static func playLabel(isSeries: Bool, entry: LibraryEntry?, episodes: [LibraryEntry]) -> String {
        guard let entry else { return String(localized: "Lecture") }
        let resumes = entry.userData.playbackPositionTicks > 0 && !entry.userData.played
        guard isSeries else { return resumes ? String(localized: "Reprendre") : String(localized: "Lecture") }
        let hasHistory = episodes.contains { $0.userData.played || $0.userData.playbackPositionTicks > 0 }
        guard let season = entry.item.parentIndexNumber, let number = entry.item.indexNumber else {
            return hasHistory ? String(localized: "Reprendre") : String(localized: "Lecture")
        }
        return resumes
            ? String(localized: "Reprendre S\(season) · E\(number)")
            : String(localized: "Lecture S\(season) · E\(number)")
    }

    // MARK: Pieces

    static func header(item: MediaItem, detail: ItemDetail?, seasonCount: Int?, imageURL: ImageURL) -> DetailHeaderModel {
        DetailHeaderModel(
            id: item.id,
            title: item.name,
            logo: imageURL(item.id, .logo, detail?.logoImageTag, logoImageWidth),
            backdrop: ArtworkSource(url: imageURL(item.id, .backdrop, detail?.backdropImageTag, backdropImageWidth), placeholderTitle: item.name),
            overview: detail?.overview ?? "",
            rating: detail?.communityRating,
            certification: detail?.officialRating,
            yearText: yearText(start: detail?.productionYear, end: detail?.endYear),
            runtimeMinutes: item.runtimeTicks.map { Int($0 / 600_000_000) },
            seasonCount: seasonCount,
            genres: detail?.genres ?? []
        )
    }

    static func yearText(start: Int?, end: Int?) -> String? {
        guard let start else { return nil }
        guard let end, end != start else { return String(start) }
        return "\(start) – \(end)"
    }

    static func episode(_ entry: LibraryEntry, imageURL: ImageURL) -> LandscapeModel {
        let item = entry.item
        let title = item.indexNumber.map { "\($0). \(item.name)" } ?? item.name
        let runtime = item.runtimeTicks.flatMap { MediaFormat.runtime(minutes: Int($0 / 600_000_000)) }
        return LandscapeModel(
            id: item.id,
            title: title,
            subtitle: HomeMapper.remainingText(entry) ?? runtime,
            image: ArtworkSource(url: imageURL(item.id, .primary, item.primaryImageTag, episodeImageWidth), placeholderTitle: title),
            progress: entry.userData.progress(runtimeTicks: item.runtimeTicks),
            isWatched: entry.userData.played
        )
    }
}
