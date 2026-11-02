import Foundation
import JellyfinAPI
import Testing
@testable import LibraryKit

@Suite struct LibraryTests {
    private func view(_ id: String, _ name: String, _ type: CollectionType?) -> BaseItemDto {
        BaseItemDto(collectionType: type, id: id, name: name)
    }

    @Test func keepsOnlyMoviesAndTVShowsInServerOrder() {
        let views = [
            view("films", "Films", .movies),
            view("music", "Musique", .music),
            view("series", "Séries", .tvshows),
            view("clips", "Clips", .musicvideos),
            view("books", "Livres", .books),
            view("photos", "Photos", .photos),
            view("mixed", "Mixte", nil),
            view("home", "Vidéos perso", .homevideos),
            view("playlists", "Playlists", .playlists),
        ]
        #expect(Library.videoLibraries(from: views) == [
            Library(id: "films", name: "Films", kind: .movies),
            Library(id: "series", name: "Séries", kind: .tvshows),
        ])
    }

    @Test func dropsViewsWithoutIdOrName() {
        let unnamed = BaseItemDto(collectionType: .movies, id: "x")
        #expect(Library.videoLibraries(from: [unnamed]).isEmpty)
    }

    @Test func shelfKeysAreCodableAndDistinctPerLibrary() throws {
        let keys: [ShelfKey] = [.continueWatching, .latestIn(libraryId: "a"), .latestIn(libraryId: "b"), .recentGrid(libraryId: "a")]
        let decoded = try JSONDecoder().decode([ShelfKey].self, from: JSONEncoder().encode(keys))
        #expect(decoded == keys)
        #expect(Set(keys).count == 4)
    }
}
