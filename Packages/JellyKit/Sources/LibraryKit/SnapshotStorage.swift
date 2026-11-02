import CryptoKit
import Foundation

/// Where snapshot bytes live, one blob per owner (server + user). An abstraction so the tvOS storage
/// spike (data-plan §3.4) can swap the location, and tests can use a temporary directory.
public protocol SnapshotStorage: Sendable {
    func read(owner: String) throws -> Data?
    func write(_ data: Data, owner: String) throws
    func remove(owner: String) throws
}

/// One JSON file per owner under `root/<sha256(owner)>/home.json`, written atomically.
/// At most `maxOwners` owners are kept; the least recently written is evicted first.
public struct FileSnapshotStorage: SnapshotStorage {
    public static let maxOwners = 5

    private let root: URL
    private let maxOwners: Int

    public init(root: URL, maxOwners: Int = FileSnapshotStorage.maxOwners) {
        self.root = root
        self.maxOwners = maxOwners
    }

    /// `Caches/jellyfuse`: the only place tvOS lets an app write reliably, and purgeable by the system,
    /// which is fine for a cache (a purge is a cold start).
    public static func inCaches() throws -> FileSnapshotStorage {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileSnapshotStorage(root: caches.appending(path: "jellyfuse", directoryHint: .isDirectory))
    }

    public func read(owner: String) throws -> Data? {
        let file = fileURL(owner)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    public func write(_ data: Data, owner: String) throws {
        let directory = directoryURL(owner)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(owner), options: .atomic)
        try evictOldOwners(keeping: directory)
    }

    public func remove(owner: String) throws {
        let directory = directoryURL(owner)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func directoryURL(_ owner: String) -> URL {
        let digest = SHA256.hash(data: Data(owner.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return root.appending(path: name, directoryHint: .isDirectory)
    }

    private func fileURL(_ owner: String) -> URL {
        directoryURL(owner).appending(path: "home.json")
    }

    private func evictOldOwners(keeping current: URL) throws {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)
        guard directories.count > maxOwners else { return }
        let dated = directories.map { url in
            (url, (try? url.appending(path: "home.json").resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast)
        }
        let victims = dated.filter { $0.0.standardizedFileURL != current.standardizedFileURL }
            .sorted { $0.1 < $1.1 }
            .prefix(directories.count - maxOwners)
        for (url, _) in victims { try FileManager.default.removeItem(at: url) }
    }
}
