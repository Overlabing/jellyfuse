import Foundation
import JellyfinAPI

/// What a library grid sorts on. The default direction is the natural one for the field.
public enum LibrarySortField: String, Sendable, Hashable, Codable, CaseIterable {
    case name
    case dateAdded
    case year
    case rating

    /// Name reads A to Z; dates and ratings read newest and best first.
    public var defaultDirection: SortDirection {
        self == .name ? .ascending : .descending
    }
}

public enum SortDirection: String, Sendable, Hashable, Codable {
    case ascending
    case descending

    public var toggled: SortDirection { self == .ascending ? .descending : .ascending }
}

public struct LibrarySort: Sendable, Hashable, Codable {
    public var field: LibrarySortField
    public var direction: SortDirection

    public init(_ field: LibrarySortField, _ direction: SortDirection? = nil) {
        self.field = field
        self.direction = direction ?? field.defaultDirection
    }

    public static let `default` = LibrarySort(.name)

    /// The « Aller à la lettre » jump only makes sense on an A-Z list.
    public var supportsLetterJump: Bool { field == .name && direction == .ascending }
}

/// KISS filters of the library panel; both off shows everything.
public struct LibraryFilter: Sendable, Hashable, Codable {
    public var unwatchedOnly: Bool
    public var favoritesOnly: Bool

    public init(unwatchedOnly: Bool = false, favoritesOnly: Bool = false) {
        self.unwatchedOnly = unwatchedOnly
        self.favoritesOnly = favoritesOnly
    }

    public static let none = LibraryFilter()
    public var isActive: Bool { unwatchedOnly || favoritesOnly }
}

/// Which items a grid lists.
public enum GridScope: Sendable, Hashable {
    /// Every movie (`.movies`) or series (`.tvshows`) of the user, across all libraries of that type.
    case library(Library.Kind)
    /// The collections (boxsets) of the collections library.
    case collections(libraryId: String)
    /// The movies and series inside one collection.
    case collection(id: String)
    /// The movies and series a person is credited on.
    case person(id: String)
}

/// One paginated resource of the store: a scope with its sort, filters and optional alphabet jump.
/// The whole value is the cache key, so changing the sort never invalidates another sort's pages.
public struct GridKey: Sendable, Hashable {
    public var scope: GridScope
    public var sort: LibrarySort
    public var filter: LibraryFilter
    /// « Aller à la lettre »: the list starts at the first name from this letter on. Nil = from the start.
    public var startsAt: String?

    public init(_ scope: GridScope, sort: LibrarySort = .default, filter: LibraryFilter = .none, startsAt: String? = nil) {
        self.scope = scope
        self.sort = sort
        self.filter = filter
        self.startsAt = startsAt
    }

    public var query: ItemsQuery {
        var query = ItemsQuery(sort: sort, filter: filter, startsAt: startsAt)
        switch scope {
        case .library(let kind):
            query.itemTypes = kind == .tvshows ? [.series] : [.movie]
        case .collections(let libraryId):
            query.itemTypes = [.boxSet]
            query.parentId = libraryId
        case .collection(let id):
            query.itemTypes = [.movie, .series]
            query.parentId = id
        case .person(let id):
            query.itemTypes = [.movie, .series]
            query.personIds = [id]
        }
        return query
    }
}

/// A `/Items` request in Jellyfuse terms; `parameters(...)` is its one translation to the SDK.
public struct ItemsQuery: Sendable, Equatable {
    public var parentId: String?
    public var itemTypes: [BaseItemKind] = []
    public var personIds: [String] = []
    public var sortBy: [ItemSortBy]
    public var sortOrder: [JellyfinAPI.SortOrder]
    public var unwatchedOnly: Bool
    public var favoritesOnly: Bool
    public var nameStartsWithOrGreater: String?

    init(sort: LibrarySort, filter: LibraryFilter, startsAt: String?) {
        let direction: JellyfinAPI.SortOrder = sort.direction == .ascending ? .ascending : .descending
        // Ties (same year, same rating) fall back to the name, always A to Z.
        switch sort.field {
        case .name: sortBy = [.sortName]
        case .dateAdded: sortBy = [.dateCreated, .sortName]
        case .year: sortBy = [.productionYear, .sortName]
        case .rating: sortBy = [.communityRating, .sortName]
        }
        sortOrder = [direction] + Array(repeating: .ascending, count: sortBy.count - 1)
        unwatchedOnly = filter.unwatchedOnly
        favoritesOnly = filter.favoritesOnly
        // The jump only exists on an A-Z list: any other order ignores it.
        nameStartsWithOrGreater = sort.supportsLetterJump ? startsAt : nil
    }

    func parameters(userID: String, startIndex: Int, limit: Int, imageTypes: [ImageType]) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.isRecursive = true
        parameters.sortBy = sortBy
        parameters.sortOrder = sortOrder
        parameters.parentID = parentId
        parameters.includeItemTypes = itemTypes
        parameters.personIDs = personIds.isEmpty ? nil : personIds
        parameters.isPlayed = unwatchedOnly ? false : nil
        parameters.isFavorite = favoritesOnly ? true : nil
        parameters.nameStartsWithOrGreater = nameStartsWithOrGreater
        parameters.enableImageTypes = imageTypes
        parameters.enableTotalRecordCount = true
        return parameters
    }
}

/// One page of `/Items`: the entries and the server-side total they are a slice of.
public struct ItemsPage: Sendable, Equatable {
    public let entries: [LibraryEntry]
    public let total: Int

    public init(entries: [LibraryEntry], total: Int) {
        self.entries = entries
        self.total = total
    }
}
