import Foundation
import Observation

/// Home shelves the store loads. Each maps to a `ResourceKind` (freshness, persistence).
public enum ShelfKey: String, Sendable, CaseIterable, Codable {
    case continueWatching
    case nextUp
    case recentlyAdded

    public var kind: ResourceKind {
        switch self {
        case .continueWatching: .continueWatching
        case .nextUp: .nextUp
        case .recentlyAdded: .recentlyAdded
        }
    }
}

/// The one cache of server data for a signed-in user (data-plan §2). Lists hold ids, items and user
/// data live in dictionaries, so a watched-state patch touches one entry and every shelf follows.
/// One instance per session: changing user means dropping it and building another; each owner's
/// snapshot stays on disk.
@MainActor
@Observable
public final class LibraryStore {
    public static let shelfLimit = 20

    public private(set) var items: [String: MediaItem] = [:]
    public private(set) var userData: [String: UserData] = [:]
    @ObservationIgnored private var shelves: [ShelfKey: Stamped<[String]>] = [:]
    /// Bumped on every shelf change so views reading `shelf(_:)` are invalidated.
    private var revision = 0

    public let owner: String
    @ObservationIgnored private let api: any LibraryAPI
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let reachability: ServerReachability?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let persistDelay: Duration
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private var inflight: [ShelfKey: Task<Void, any Error>] = [:]
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    /// Hydrates from the owner's snapshot, if any: shelves come back stale, so the screen paints
    /// from disk and `ensureFresh` revalidates.
    public init(
        owner: String,
        api: any LibraryAPI,
        storage: any SnapshotStorage,
        reachability: ServerReachability? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        persistDelay: Duration = .seconds(1),
        retryDelays: [Duration] = [.seconds(1), .seconds(2)]
    ) {
        self.owner = owner
        self.api = api
        self.snapshots = SnapshotStore(storage: storage)
        self.reachability = reachability
        self.now = now
        self.persistDelay = persistDelay
        self.retryDelays = retryDelays
        hydrate()
    }

    // MARK: Reads (synchronous, from memory)

    public func shelf(_ key: ShelfKey) -> [String] {
        _ = revision
        return shelves[key]?.value ?? []
    }

    /// The items of a shelf joined with their user data, in server order.
    public func entries(_ key: ShelfKey) -> [LibraryEntry] {
        shelf(key).compactMap { id in items[id].map { LibraryEntry(item: $0, userData: userData[id] ?? .none) } }
    }

    /// Never loaded counts as stale.
    public func isStale(_ key: ShelfKey) -> Bool {
        guard let stamped = shelves[key] else { return true }
        return stamped.isStale(for: key.kind, now: now())
    }

    // MARK: Loading

    /// Loads the shelf unless it is fresh (or `force`). Concurrent calls share one request. Offline,
    /// nothing is launched and nothing fails: the cache stays on screen.
    public func ensureFresh(_ key: ShelfKey, force: Bool = false) async throws {
        guard force || isStale(key) else { return }
        if let task = inflight[key] {
            try await settle(task, for: key)
            return
        }
        if let reachability, !reachability.isOnline { return }
        let task = Task { try await self.load(key) }
        inflight[key] = task
        try await settle(task, for: key)
    }

    /// Waits for a load, then forgets it unless a newer one replaced it. A cancelled load is not an error.
    private func settle(_ task: Task<Void, any Error>, for key: ShelfKey) async throws {
        defer { if inflight[key] == task { inflight[key] = nil } }
        do {
            try await task.value
        } catch is CancellationError {
            return
        }
    }

    private func load(_ key: ShelfKey) async throws {
        let entries: [LibraryEntry]
        do {
            entries = try await fetch(key)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            reachability?.reportFailure(error)
            throw error
        }
        // A patch cancelled this request: its answer predates the patch and must not overwrite it.
        guard !Task.isCancelled else { throw CancellationError() }
        reachability?.reportSuccess()
        install(entries, into: key)
    }

    /// GETs retry on transport errors only (1 s, then 2 s), never on an HTTP answer.
    private func fetch(_ key: ShelfKey) async throws -> [LibraryEntry] {
        var delays = retryDelays[...]
        while true {
            do {
                switch key {
                case .continueWatching: return try await api.resume(limit: Self.shelfLimit)
                case .nextUp: return try await api.nextUp(limit: Self.shelfLimit)
                case .recentlyAdded: return try await api.latestMedia(limit: Self.shelfLimit)
                }
            } catch {
                guard UserFacingError.isNetwork(error), let delay = delays.popFirst() else { throw error }
                try await Task.sleep(for: delay)
            }
        }
    }

    private func install(_ entries: [LibraryEntry], into key: ShelfKey) {
        for entry in entries {
            items[entry.item.id] = entry.item
            userData[entry.item.id] = entry.userData
        }
        shelves[key] = Stamped(entries.map(\.item.id), fetchedAt: now())
        revision += 1
        schedulePersist(for: key.kind)
    }

    // MARK: Invalidation and mutation

    /// Marks the shelves of these kinds stale; the next `ensureFresh` refetches them.
    public func markStale(_ kinds: Set<ResourceKind>) {
        for (key, stamped) in shelves where kinds.contains(key.kind) {
            shelves[key] = Stamped(stamped.value, fetchedAt: .distantPast)
        }
        revision += 1
    }

    /// Optimistic user-data mutation (data-plan §5.6): cancel in-flight loads, snapshot the entries,
    /// patch locally (offline included), call the server. Success marks `invalidating` stale; failure
    /// restores the snapshot and rethrows, without invalidating.
    public func mutateUserData(
        _ ids: [String],
        invalidating kinds: Set<ResourceKind>,
        transform: (UserData) -> UserData,
        call: () async throws -> Void
    ) async throws {
        for (key, task) in inflight where kinds.contains(key.kind) {
            task.cancel()
            inflight[key] = nil
        }
        let before = Dictionary(uniqueKeysWithValues: ids.map { ($0, userData[$0]) })
        for id in ids { userData[id] = transform(userData[id] ?? .none) }
        do {
            try await call()
        } catch {
            for (id, old) in before { userData[id] = old }
            throw error
        }
        markStale(kinds)
    }

    /// Local-only patch of one item's user data, kept even offline (data-plan §5.1 rule 5: a stop is
    /// reflected at once, the server's answer comes later). In-flight loads are cancelled: their answer
    /// predates the patch. Unknown items are ignored.
    public func patchUserData(_ id: String, transform: (UserData) -> UserData) {
        guard items[id] != nil || userData[id] != nil else { return }
        for (key, task) in inflight {
            task.cancel()
            inflight[key] = nil
        }
        userData[id] = transform(userData[id] ?? .none)
    }

    // MARK: Persistence

    private func hydrate() {
        guard let snapshot = snapshots.load(owner: owner, now: now()) else { return }
        items = snapshot.items
        userData = snapshot.userData
        for shelf in snapshot.shelves {
            shelves[shelf.key] = Stamped(shelf.ids, fetchedAt: .distantPast)
        }
    }

    private func schedulePersist(for kind: ResourceKind) {
        guard kind.isPersisted else { return }
        persistTask?.cancel()
        persistTask = Task { [persistDelay] in
            try? await Task.sleep(for: persistDelay)
            guard !Task.isCancelled else { return }
            self.persistNow()
        }
    }

    /// Writes the allowlisted shelves and what they reference. Failures are ignored: it is only a cache.
    public func persistNow() {
        persistTask?.cancel()
        let persisted = shelves.filter { $0.key.kind.isPersisted }
        let ids = Set(persisted.values.flatMap(\.value))
        let snapshot = LibrarySnapshot(
            schemaVersion: LibrarySnapshot.currentVersion,
            savedAt: now(),
            owner: owner,
            shelves: persisted.map { .init(key: $0.key, ids: $0.value.value) }.sorted { $0.key.rawValue < $1.key.rawValue },
            items: items.filter { ids.contains($0.key) },
            userData: userData.filter { ids.contains($0.key) }
        )
        try? snapshots.save(snapshot)
    }
}
