/// The network surface the store depends on. `JellyfinClient` is the real one; tests inject a fake.
public protocol LibraryAPI: Sendable {
    func resume(limit: Int) async throws -> [LibraryEntry]
    func nextUp(limit: Int) async throws -> [LibraryEntry]
    func latestMedia(limit: Int) async throws -> [LibraryEntry]
}

extension JellyfinClient: LibraryAPI {}
