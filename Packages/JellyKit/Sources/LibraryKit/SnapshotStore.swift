import Foundation

/// The persisted slice of a `LibraryStore`: allowlisted shelves (ids) and the items / user data they reference.
struct LibrarySnapshot: Codable, Equatable {
    struct Shelf: Codable, Equatable {
        var key: ShelfKey
        var ids: [String]
    }

    /// Bump when any persisted model changes shape: the cache is disposable, old snapshots are dropped, never migrated.
    ///
    /// v2: `ShelfKey` became an enum with per-library cases and the library list joined the snapshot.
    /// A v1 snapshot fails the version check (and would fail to decode its keys): dropped, cold start.
    static let currentVersion = 2
    /// Snapshots older than this are ignored (RN `PERSIST_MAX_AGE_MS`).
    static let maxAge: TimeInterval = 30 * 24 * 3600

    var schemaVersion: Int
    var savedAt: Date
    var owner: String
    var libraries: [Library]
    var shelves: [Shelf]
    var items: [String: MediaItem]
    var userData: [String: UserData]
}

/// Reads and writes the snapshot of one owner. Anything unreadable, foreign, outdated or too old is
/// discarded and deleted: a cold start is the worst case.
struct SnapshotStore: Sendable {
    let storage: any SnapshotStorage

    func load(owner: String, now: Date) -> LibrarySnapshot? {
        guard let data = try? storage.read(owner: owner) else { return nil }
        guard
            let snapshot = try? JSONDecoder.snapshot.decode(LibrarySnapshot.self, from: data),
            snapshot.schemaVersion == LibrarySnapshot.currentVersion,
            snapshot.owner == owner,
            now.timeIntervalSince(snapshot.savedAt) <= LibrarySnapshot.maxAge
        else {
            try? storage.remove(owner: owner)
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        try storage.write(JSONEncoder.snapshot.encode(snapshot), owner: snapshot.owner)
    }
}

private extension JSONEncoder {
    static var snapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var snapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
