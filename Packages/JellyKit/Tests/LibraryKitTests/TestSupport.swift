import Foundation
@testable import LibraryKit

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

func entry(_ id: String, position: Int64 = 0, runtime: Int64 = 1000) -> LibraryEntry {
    LibraryEntry(
        item: MediaItem(id: id, name: "Item \(id)", runtimeTicks: runtime),
        userData: UserData(played: false, playbackPositionTicks: position, playCount: 0, isFavorite: false, lastPlayedDate: nil)
    )
}

/// Scripted `LibraryAPI`: counts calls, can fail with queued errors, and can hold answers until released.
actor FakeAPI: LibraryAPI {
    private(set) var calls: [String] = []
    var resumeResult: [LibraryEntry] = []
    var nextUpResult: [LibraryEntry] = []
    var latestResults: [String: [LibraryEntry]] = [:]
    var gridResults: [String: [LibraryEntry]] = [:]
    var librariesResult: [Library] = []
    var errors: [any Error] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var gated = false
    private var arrived: CheckedContinuation<Void, Never>?

    func setResume(_ value: [LibraryEntry]) { resumeResult = value }
    func setLatest(_ value: [LibraryEntry], in id: String) { latestResults[id] = value }
    func setGrid(_ value: [LibraryEntry], in id: String) { gridResults[id] = value }
    func setLibraries(_ value: [Library]) { librariesResult = value }
    func queueErrors(_ list: [any Error]) { errors = list }
    func holdAnswers() { gated = true }
    func releaseAnswers() { gated = false; gate?.resume(); gate = nil }
    func callCount(_ name: String) -> Int { calls.filter { $0 == name }.count }

    /// Returns once a call is parked on the gate.
    func waitUntilParked() async {
        if gate != nil { return }
        await withCheckedContinuation { arrived = $0 }
    }

    private func answer(_ name: String, _ value: [LibraryEntry]) async throws -> [LibraryEntry] {
        try await gate(name)
        return value
    }

    private func gate(_ name: String) async throws {
        calls.append(name)
        if !errors.isEmpty { throw errors.removeFirst() }
        if gated {
            await withCheckedContinuation { continuation in
                gate = continuation
                arrived?.resume()
                arrived = nil
            }
        }
    }

    func resume(limit: Int) async throws -> [LibraryEntry] { try await answer("resume", resumeResult) }
    func nextUp(limit: Int) async throws -> [LibraryEntry] { try await answer("nextUp", nextUpResult) }
    func libraries() async throws -> [Library] {
        try await gate("libraries")
        return librariesResult
    }
    func latest(in libraryId: String, limit: Int) async throws -> [LibraryEntry] {
        try await answer("latest:\(libraryId)", latestResults[libraryId] ?? [])
    }
    func recentlyAdded(in libraryId: String, limit: Int) async throws -> [LibraryEntry] {
        try await answer("grid:\(libraryId)", gridResults[libraryId] ?? [])
    }
}

func temporaryStorage(maxOwners: Int = FileSnapshotStorage.maxOwners) -> (FileSnapshotStorage, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "jellyfuse-tests-\(UUID().uuidString)")
    return (FileSnapshotStorage(root: root, maxOwners: maxOwners), root)
}
