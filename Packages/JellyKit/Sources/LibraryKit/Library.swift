import JellyfinAPI

/// A Jellyfin library (user view) Jellyfuse shows. Video only: movies and TV shows, plus the collections
/// (boxsets) view, which only the Films tab uses.
public struct Library: Sendable, Equatable, Hashable, Identifiable, Codable {
    public enum Kind: String, Sendable, Equatable, Hashable, Codable {
        case movies
        case tvshows
        case boxsets
    }

    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

extension Library {
    /// Libraries that get an « Ajouts récents » shelf on the home: movies and shows, never collections.
    public var showsOnHome: Bool { kind != .boxsets }

    /// The video libraries among the user's views, in the server's order. Music, music videos, books,
    /// photos and every other collection type are dropped, and so are mixed libraries (no collection
    /// type): Jellyfuse is movies, TV shows and their collections only.
    static func videoLibraries(from views: [BaseItemDto]) -> [Library] {
        views.compactMap { dto in
            guard let id = dto.id, let name = dto.name, let type = dto.collectionType else { return nil }
            switch type {
            case .movies: return Library(id: id, name: name, kind: .movies)
            case .tvshows: return Library(id: id, name: name, kind: .tvshows)
            case .boxsets: return Library(id: id, name: name, kind: .boxsets)
            default: return nil
            }
        }
    }
}
