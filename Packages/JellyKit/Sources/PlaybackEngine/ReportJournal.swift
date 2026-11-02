import Foundation
import JellyfinAPI

/// Where the journal's bytes live. Not `Caches` (the system may purge it, losing unsent reports):
/// the journal is small after coalescing and must survive (data-plan §3.4).
public protocol ReportJournalStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

/// `UserDefaults`-backed storage (documented cap 500 KB; a coalesced journal is a few KB).
public struct UserDefaultsJournalStorage: ReportJournalStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "jellyfuse.reportJournal.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> Data? { defaults.data(forKey: key) }
    public func save(_ data: Data) throws { defaults.set(data, forKey: key) }
}

enum ReportKind: String, Codable, Sendable { case start, progress, stopped }

/// The fields of one report, whatever its kind. `itemId` is the item's id and `mediaSourceId` the
/// source's: two different ids.
struct ReportPayload: Codable, Sendable, Equatable {
    var itemId: String
    var mediaSourceId: String
    var playSessionId: String
    var playMethod: PlayMethod
    var positionTicks: Int64
    var isPaused: Bool
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    /// Start and Progress share the SDK's `PlaybackStateInfo`. The SDK has no `EventName`: none is sent.
    var stateInfo: PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: audioStreamIndex, canSeek: true, isPaused: isPaused,
            itemID: itemId, mediaSourceID: mediaSourceId, playMethod: playMethod,
            playSessionID: playSessionId, positionTicks: Int(positionTicks),
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    /// `PlaybackStopInfo` has no track indexes: only Progress persists them server-side.
    var stopInfo: PlaybackStopInfo {
        PlaybackStopInfo(
            itemID: itemId, mediaSourceID: mediaSourceId, playSessionID: playSessionId,
            positionTicks: Int(positionTicks)
        )
    }
}

/// A report waiting in the journal, and the handle to remove it once the server accepted it.
struct PendingReport: Sendable, Equatable {
    var owner: String
    var playSessionId: String
    var kind: ReportKind
    var revision: Int
    var payload: ReportPayload
}

/// The unsent reports, coalesced per play session: at most Start (if it could not go), the last
/// Progress and the Stopped (data-plan §5.3). A two-hour outage is three entries, not 1 440.
/// A reference type confined to its owner (`PlaybackReporter`): no isolation of its own.
final class ReportJournal {
    static let maxSessions = 50

    private struct Slot: Codable { var payload: ReportPayload; var revision: Int }
    private struct Record: Codable {
        var owner: String
        var playSessionId: String
        var start: Slot?
        var progress: Slot?
        var stopped: Slot?
        var isEmpty: Bool { start == nil && progress == nil && stopped == nil }
    }
    private struct File: Codable { var nextRevision: Int; var records: [Record] }

    private let storage: any ReportJournalStorage
    private let maxSessions: Int
    private var file: File

    init(storage: any ReportJournalStorage, maxSessions: Int = ReportJournal.maxSessions) {
        self.storage = storage
        self.maxSessions = maxSessions
        // An unreadable journal is dropped rather than blocking playback reports forever.
        file = ((try? storage.load()) ?? nil).flatMap { try? JSONDecoder().decode(File.self, from: $0) }
            ?? File(nextRevision: 1, records: [])
    }

    /// Records a report, persisting before the caller attempts to send it.
    func record(owner: String, kind: ReportKind, payload: ReportPayload) {
        let slot = Slot(payload: payload, revision: file.nextRevision)
        file.nextRevision += 1
        let id = payload.playSessionId
        let position: Int
        if let existing = file.records.firstIndex(where: { $0.owner == owner && $0.playSessionId == id }) {
            position = existing
        } else {
            file.records.append(Record(owner: owner, playSessionId: id))
            position = file.records.count - 1
        }
        switch kind {
        case .start: file.records[position].start = slot
        case .progress:
            // A Progress after the Stopped of the same session is stale.
            if file.records[position].stopped == nil { file.records[position].progress = slot }
        case .stopped: file.records[position].stopped = slot
        }
        if file.records.count > maxSessions { file.records.removeFirst(file.records.count - maxSessions) }
        persist()
    }

    /// The oldest report of `owner`: sessions in recording order, Start, then Progress, then Stopped.
    /// A Progress superseded by a Stopped is discarded here, never sent.
    func next(owner: String) -> PendingReport? {
        var dropped = false
        defer { if dropped { persist() } }
        for index in file.records.indices where file.records[index].owner == owner {
            if file.records[index].stopped != nil, file.records[index].progress != nil {
                file.records[index].progress = nil
                dropped = true
            }
            let record = file.records[index]
            for (kind, slot) in [(ReportKind.start, record.start), (.progress, record.progress), (.stopped, record.stopped)] {
                if let slot {
                    return PendingReport(owner: owner, playSessionId: record.playSessionId, kind: kind, revision: slot.revision, payload: slot.payload)
                }
            }
        }
        return nil
    }

    /// Removes a report the server accepted (or refused for good). A newer report in the same slot stays.
    func complete(_ report: PendingReport) {
        guard let index = file.records.firstIndex(where: { $0.owner == report.owner && $0.playSessionId == report.playSessionId }) else { return }
        switch report.kind {
        case .start where file.records[index].start?.revision == report.revision: file.records[index].start = nil
        case .progress where file.records[index].progress?.revision == report.revision: file.records[index].progress = nil
        case .stopped where file.records[index].stopped?.revision == report.revision: file.records[index].stopped = nil
        default: return
        }
        if file.records[index].isEmpty { file.records.remove(at: index) }
        persist()
    }

    /// Kinds waiting for `owner`, per session, for tests and diagnostics.
    func pendingKinds(owner: String) -> [[ReportKind]] {
        file.records.filter { $0.owner == owner }.map { record in
            [(ReportKind.start, record.start), (.progress, record.progress), (.stopped, record.stopped)].compactMap { $1 == nil ? nil : $0 }
        }
    }

    /// Failures are ignored: reporting must never break playback.
    private func persist() {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? storage.save(data)
    }
}
