import Foundation
import JellyfinAPI

/// Quasi-immutable metadata of a Jellyfin item. Watched state, progress and favorite live in
/// `UserData`, stored once per item id (data-plan D2).
public struct MediaItem: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case movie
        case series
        case season
        case episode
        /// A Jellyfin collection: opens a screen listing its movies, not a detail screen.
        case boxSet
    }

    public let id: String
    public let name: String
    public let seriesName: String?
    public let primaryImageTag: String?
    public let runtimeTicks: Int64?
    /// Nil for anything that is not a movie, series, season or episode.
    public let kind: Kind?
    /// Episodes and seasons: the series they belong to.
    public let seriesId: String?
    /// Episodes: the season they belong to.
    public let seasonId: String?
    /// Episode number within its season, season number within its series.
    public let indexNumber: Int?
    /// Episodes: the season number.
    public let parentIndexNumber: Int?
    /// The title as an image (Jellyfin `Logo`): the item's own, else its parent's (an episode shows its series' logo).
    public let logoImageTag: String?
    /// The item that carries the logo; nil when it is the item itself.
    public let logoItemId: String?

    public init(
        id: String, name: String, seriesName: String? = nil, primaryImageTag: String? = nil,
        runtimeTicks: Int64? = nil, kind: Kind? = nil, seriesId: String? = nil, seasonId: String? = nil,
        indexNumber: Int? = nil, parentIndexNumber: Int? = nil,
        logoImageTag: String? = nil, logoItemId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.seriesName = seriesName
        self.primaryImageTag = primaryImageTag
        self.runtimeTicks = runtimeTicks
        self.kind = kind
        self.seriesId = seriesId
        self.seasonId = seasonId
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.logoImageTag = logoImageTag
        self.logoItemId = logoItemId
    }
}

/// A cast or crew member credited on an item (`BaseItemDto.people`). Only actors and directors are kept.
public struct Person: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case actor
        case director
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// The character an actor plays; nil for a director or when the server has none.
    public let role: String?
    public let primaryImageTag: String?

    public init(id: String, name: String, kind: Kind, role: String? = nil, primaryImageTag: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
        self.primaryImageTag = primaryImageTag
    }
}

extension Person {
    /// Nil for anything but an actor or a director, or without an id or a name.
    init?(dto: BaseItemPerson) {
        guard let id = dto.id, let name = dto.name, !name.isEmpty else { return nil }
        let kind: Kind
        switch dto.type {
        case .actor: kind = .actor
        case .director: kind = .director
        default: return nil
        }
        let role = dto.role.flatMap { $0.isEmpty ? nil : $0 }
        self.init(id: id, name: name, kind: kind, role: role, primaryImageTag: dto.primaryImageTag)
    }
}

/// The on-demand extras of the detail screen: loaded with `/Items/{id}`, never part of a shelf, so they
/// are not stored in the shared `items` dictionary (a shelf reload must not erase them).
public struct ItemDetail: Sendable, Equatable {
    public let item: MediaItem
    public let overview: String?
    public let productionYear: Int?
    /// Series that ended: the last year of the run.
    public let endYear: Int?
    public let communityRating: Double?
    public let officialRating: String?
    public let genres: [String]
    public let backdropImageTag: String?
    /// The title as an image (Jellyfin `Logo`); the screen falls back to text without it.
    public let logoImageTag: String?
    /// Actors and directors, in the server's order.
    public let people: [Person]
    /// Chapter marks, by start time.
    public let chapters: [Chapter]

    public init(
        item: MediaItem, overview: String? = nil, productionYear: Int? = nil, endYear: Int? = nil,
        communityRating: Double? = nil, officialRating: String? = nil, genres: [String] = [],
        backdropImageTag: String? = nil, logoImageTag: String? = nil, people: [Person] = [],
        chapters: [Chapter] = []
    ) {
        self.item = item
        self.overview = overview
        self.productionYear = productionYear
        self.endYear = endYear
        self.communityRating = communityRating
        self.officialRating = officialRating
        self.genres = genres
        self.backdropImageTag = backdropImageTag
        self.logoImageTag = logoImageTag
        self.people = people
        self.chapters = chapters
    }
}

/// A chapter mark of a video.
public struct Chapter: Sendable, Equatable {
    /// Jellyfin names unnamed chapters « Chapter 3 » on its own; nil when the server sent none.
    public let name: String?
    public let startSeconds: Double

    public init(name: String?, startSeconds: Double) {
        self.name = name
        self.startSeconds = startSeconds
    }

    /// 100-nanosecond ticks to seconds.
    init?(dto: ChapterInfo) {
        guard let ticks = dto.startPositionTicks else { return nil }
        self.init(name: dto.name, startSeconds: Double(ticks) / 10_000_000)
    }
}

/// An item as the server returns it: metadata plus the user's own data, ready to be split into the store.
public struct LibraryEntry: Sendable, Equatable {
    public let item: MediaItem
    public let userData: UserData

    public init(item: MediaItem, userData: UserData = .none) {
        self.item = item
        self.userData = userData
    }
}

extension LibraryEntry {
    init?(dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        let logo = MediaItem.logo(of: dto)
        self.init(
            item: MediaItem(
                id: id,
                name: dto.name ?? "",
                seriesName: dto.seriesName,
                primaryImageTag: dto.imageTags?["Primary"],
                runtimeTicks: dto.runTimeTicks.map(Int64.init),
                kind: dto.type.flatMap(MediaItem.Kind.init(kind:)),
                seriesId: dto.seriesID,
                seasonId: dto.seasonID,
                indexNumber: dto.indexNumber,
                parentIndexNumber: dto.parentIndexNumber,
                logoImageTag: logo?.tag,
                logoItemId: logo?.itemId
            ),
            userData: dto.userData.map(UserData.init(dto:)) ?? .none
        )
    }
}

extension MediaItem {
    /// The item's own logo, else the parent's (both tag and carrier id are needed to build its URL).
    static func logo(of dto: BaseItemDto) -> (tag: String, itemId: String?)? {
        if let tag = dto.imageTags?["Logo"] { return (tag, nil) }
        if let tag = dto.parentLogoImageTag, let parentId = dto.parentLogoItemID { return (tag, parentId) }
        return nil
    }
}

extension MediaItem.Kind {
    init?(kind: BaseItemKind) {
        switch kind {
        case .movie: self = .movie
        case .series: self = .series
        case .season: self = .season
        case .episode: self = .episode
        case .boxSet: self = .boxSet
        default: return nil
        }
    }
}

extension ItemDetail {
    /// The user data comes separately, as for every item.
    init?(dto: BaseItemDto) {
        guard let entry = LibraryEntry(dto: dto) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        self.init(
            item: entry.item,
            overview: dto.overview,
            productionYear: dto.productionYear,
            endYear: dto.status == "Ended" ? dto.endDate.map { calendar.component(.year, from: $0) } : nil,
            communityRating: dto.communityRating.map(Double.init),
            officialRating: dto.officialRating,
            genres: dto.genres ?? [],
            backdropImageTag: dto.backdropImageTags?.first,
            logoImageTag: dto.imageTags?["Logo"],
            people: (dto.people ?? []).compactMap(Person.init(dto:)),
            chapters: (dto.chapters ?? []).compactMap(Chapter.init(dto:)).sorted { $0.startSeconds < $1.startSeconds }
        )
    }
}
