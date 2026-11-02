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
}

extension JellyfinClient: LibraryAPI {}
