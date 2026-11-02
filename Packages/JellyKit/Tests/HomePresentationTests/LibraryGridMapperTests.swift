import DesignSystem
import Foundation
import LibraryKit
import Testing
@testable import HomePresentation

@Suite struct LibraryGridMapperTests {
    private func imageURL(_ id: String, _ kind: ItemImageKind, _ tag: String?, _ width: Int) -> URL? {
        tag.map { URL(string: "https://srv/\(id)/\($0)/\(width)")! }
    }

    private func entry(_ id: String, played: Bool = false) -> LibraryEntry {
        LibraryEntry(
            item: MediaItem(id: id, name: "Film \(id)", primaryImageTag: "t", kind: .movie),
            userData: UserData(played: played, playbackPositionTicks: 0, playCount: 0, isFavorite: false, lastPlayedDate: nil)
        )
    }

    @Test func contentMapsEntriesToPostersAndKeepsPagingState() {
        let content = LibraryGridMapper.content(
            entries: [entry("a"), entry("b", played: true)], total: 500, isComplete: false, imageURL: imageURL
        )
        #expect(content.items.map(\.id) == ["a", "b"])
        #expect(content.items[1].isWatched)
        #expect(content.total == 500)
        #expect(!content.isComplete)
    }

    @Test func lettersAreHashThenAToZ() {
        #expect(LibraryGridMapper.letters.count == 27)
        #expect(LibraryGridMapper.letters.first == "#" && LibraryGridMapper.letters.last == "Z")
        #expect(LibraryGridMapper.startsAt(forLetter: "#") == nil)
        #expect(LibraryGridMapper.startsAt(forLetter: "M") == "M")
    }

    @Test func summaryListsSortFiltersAndJump() {
        #expect(LibraryGridMapper.summary(sort: .default, filter: .none, startsAt: nil) == "Titre A–Z")
        #expect(
            LibraryGridMapper.summary(sort: .default, filter: LibraryFilter(unwatchedOnly: true, favoritesOnly: true), startsAt: "M")
                == "Titre A–Z · Non vus · Favoris · Dès « M »"
        )
        // A jump means nothing outside A-Z order and is not announced.
        #expect(LibraryGridMapper.summary(sort: LibrarySort(.year), filter: .none, startsAt: "M") == "Année, récent d'abord")
    }

    @Test func personModelKeepsTheJellyfinPersonId() {
        let people = DetailMapper.people(
            [Person(id: "p1", name: "Ada", kind: .actor, role: "Eve"), Person(id: "p1", name: "Ada", kind: .director)],
            imageURL: imageURL
        )
        #expect(people.map(\.personId) == ["p1", "p1"])
        #expect(Set(people.map(\.id)).count == 2)
    }
}
