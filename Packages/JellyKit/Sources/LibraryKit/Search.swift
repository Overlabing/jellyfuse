import Foundation
import JellyfinAPI

/// The kinds of item the search looks for. Music and people are out of scope (ui-plan §6.6, v1).
public enum SearchKind: Sendable, CaseIterable {
    case movie
    case series
    case episode

    var sdkType: BaseItemKind {
        switch self {
        case .movie: .movie
        case .series: .series
        case .episode: .episode
        }
    }
}

/// What the user typed, once it is worth a request: trimmed, inner whitespace collapsed, at least
/// `minimumLength` characters (ui-plan §6.6: « dès 2 caractères »).
public struct SearchQuery: Sendable, Equatable {
    public static let minimumLength = 2
    /// Results per kind (ui-plan §7: `limit 12` par type).
    public static let limitPerKind = 12

    public let term: String

    public init?(_ raw: String) {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count >= Self.minimumLength else { return nil }
        term = collapsed
    }
}

/// The network surface of the search. `JellyfinClient` is the real one; tests inject a fake.
public protocol SearchAPI: Sendable {
    /// Up to `limit` items of one kind whose name matches `query`, best match first (server relevance).
    func search(_ query: SearchQuery, kind: SearchKind, limit: Int) async throws -> [LibraryEntry]
}

extension JellyfinClient: SearchAPI {}

extension JellyfinClient {
    /// The `/Items` parameters of a search: recursive over every library, one kind, server-side term match.
    package static func searchParameters(userId: String, query: SearchQuery, kind: SearchKind, limit: Int) -> Paths.GetItemsParameters {
        .init(
            userID: userId, limit: limit, isRecursive: true, searchTerm: query.term,
            includeItemTypes: [kind.sdkType], enableUserData: true,
            enableImageTypes: [.primary, .logo], enableTotalRecordCount: false
        )
    }
}

extension JellyfinClient {
    public func search(_ query: SearchQuery, kind: SearchKind, limit: Int) async throws -> [LibraryEntry] {
        let request = Paths.getItems(parameters: Self.searchParameters(userId: try currentUserId(), query: query, kind: kind, limit: limit))
        let result = try await perform(request)
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }
}
