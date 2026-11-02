import DesignSystem
import Foundation
import LibraryKit

/// A paginated poster grid as the screen shows it: what has loaded so far and whether more can come.
public struct PosterGridContent: Sendable, Equatable {
    public let items: [PosterModel]
    /// The server's total; nil before the first page.
    public let total: Int?
    public let isComplete: Bool

    public var isEmpty: Bool { items.isEmpty }

    public init(items: [PosterModel], total: Int?, isComplete: Bool) {
        self.items = items
        self.total = total
        self.isComplete = isComplete
    }
}

/// Pure mapping for the library tabs (ui-plan lot 3.5): grid items and the « Filtres et tri » texts.
public enum LibraryGridMapper {
    /// Posters left below the last visible one when the next page is requested (six rows): the next
    /// page lands before the remote reaches the end.
    public static let prefetchDistance = 36

    public static func content(entries: [LibraryEntry], total: Int?, isComplete: Bool, imageURL: HomeMapper.ImageURL) -> PosterGridContent {
        PosterGridContent(items: entries.map { HomeMapper.poster($0, imageURL: imageURL) }, total: total, isComplete: isComplete)
    }

    /// `#` (the start of the list) then A to Z: the « Aller à la lettre » choices.
    public static let letters: [String] = ["#"] + (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }

    /// The key's alphabet jump for a letter choice; `#` is the start of the list.
    public static func startsAt(forLetter letter: String) -> String? {
        letter == "#" ? nil : letter
    }

    public static func fieldLabel(_ field: LibrarySortField) -> String {
        switch field {
        case .name: String(localized: "Titre")
        case .dateAdded: String(localized: "Date d'ajout")
        case .year: String(localized: "Année")
        case .rating: String(localized: "Note")
        }
    }

    public static func directionLabel(_ direction: SortDirection) -> String {
        direction == .ascending ? String(localized: "Croissant") : String(localized: "Décroissant")
    }

    /// The sort in one phrase (`Titre A–Z`, `Ajout récent`), shown next to the panel button.
    public static func sortSummary(_ sort: LibrarySort) -> String {
        switch (sort.field, sort.direction) {
        case (.name, .ascending): String(localized: "Titre A–Z")
        case (.name, .descending): String(localized: "Titre Z–A")
        case (.dateAdded, .descending): String(localized: "Ajout récent")
        case (.dateAdded, .ascending): String(localized: "Ajout ancien")
        case (.year, .descending): String(localized: "Année, récent d'abord")
        case (.year, .ascending): String(localized: "Année, ancien d'abord")
        case (.rating, .descending): String(localized: "Mieux notés")
        case (.rating, .ascending): String(localized: "Moins bien notés")
        }
    }

    /// Sort, active filters and alphabet jump on one line: `Titre A–Z · Non vus · Dès « M »`.
    public static func summary(sort: LibrarySort, filter: LibraryFilter, startsAt: String?) -> String {
        var parts = [sortSummary(sort)]
        if filter.unwatchedOnly { parts.append(String(localized: "Non vus")) }
        if filter.favoritesOnly { parts.append(String(localized: "Favoris")) }
        if let startsAt, sort.supportsLetterJump { parts.append(String(localized: "Dès « \(startsAt) »")) }
        return parts.joined(separator: " · ")
    }
}
