/// The network surface the store depends on. `JellyfinClient` is the real one; tests inject a fake.
public protocol LibraryAPI: Sendable {
    func resume(limit: Int) async throws -> [LibraryEntry]
    func nextUp(limit: Int) async throws -> [LibraryEntry]
    /// The user's video libraries, in the server's order.
    func libraries() async throws -> [Library]
    /// Latest additions of one library (`/Items/Latest` with `parentId`).
    func latest(in libraryId: String, limit: Int) async throws -> [LibraryEntry]
    /// The top-level items of a library, newest added first.
    func recentlyAdded(in libraryId: String, limit: Int) async throws -> [LibraryEntry]
    /// The detail screen's item (`/Users/{id}/Items/{itemId}`) with the user's own data.
    func detail(of itemId: String) async throws -> (detail: ItemDetail, userData: UserData)
    /// The seasons of a series, in the server's order.
    func seasons(of seriesId: String) async throws -> [LibraryEntry]
    /// Every episode of a series, in season then episode order (one request, grouped by the caller).
    func episodes(of seriesId: String) async throws -> [LibraryEntry]
    /// Adds the item to / removes it from the user's favorites (« Ma liste »).
    func setFavorite(_ isFavorite: Bool, for itemId: String) async throws
    /// Marks the item watched / unwatched for the user.
    func setPlayed(_ isPlayed: Bool, for itemId: String) async throws
}

extension JellyfinClient: LibraryAPI {}
