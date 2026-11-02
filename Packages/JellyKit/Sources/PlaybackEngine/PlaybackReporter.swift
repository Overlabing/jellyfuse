import Foundation
import LibraryKit

/// The player's state at one instant. `-1` as a subtitle index means subtitles off; nil means unknown.
public struct PlaybackSnapshot: Sendable, Equatable {
    public var positionTicks: Int64
    public var isPaused: Bool
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?

    public init(positionTicks: Int64, isPaused: Bool = false, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil) {
        self.positionTicks = positionTicks
        self.isPaused = isPaused
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
    }

    /// Jellyfin ticks (100 ns) in one second.
    public static let ticksPerSecond: Int64 = 10_000_000

    /// A player position in seconds as ticks. Negative, NaN and infinite positions (mpv before the first
    /// frame) count as 0, so a report never carries a nonsense position.
    public static func ticks(seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(min(seconds, Double(Int64.max / ticksPerSecond)) * Double(ticksPerSecond))
    }
}

/// Why a snapshot is being reported.
public enum ProgressTrigger: Sendable, Equatable {
    /// The regular tick: sent at most once per `progressInterval`.
    case timeUpdate
    /// Pause, resume, seek or track change: sent at once.
    case immediate
}

/// Connectivity as the reporter sees it. `ServerReachability` is the real one (see `ReachabilityConnectivity`).
public protocol ReportingConnectivity: Sendable {
    func isOnline() async -> Bool
    func reportFailure(_ error: any Error) async
    func reportSuccess() async
}

public struct ReachabilityConnectivity: ReportingConnectivity {
    private let reachability: ServerReachability
    public init(_ reachability: ServerReachability) { self.reachability = reachability }
    public func isOnline() async -> Bool { await reachability.isOnline }
    public func reportFailure(_ error: any Error) async { await reachability.reportFailure(error) }
    public func reportSuccess() async { await reachability.reportSuccess() }
}

/// Reports one playback at a time to Jellyfin: Start at the first `playing`, Progress every
/// `progressInterval` plus immediately on pause/seek/track change, Stopped once (data-plan §5.1).
///
/// Every report is journaled first, then sent; it leaves the journal only once the server accepted it,
/// so a crash, an outage or a kill never loses the position. A single drain pass runs at a time, oldest
/// first, and stops at the first failure.
public actor PlaybackReporter {
    public static let defaultProgressInterval: TimeInterval = 10

    private struct Active {
        var identity: PlaybackIdentity
        var started = false
        var lastSentAt: Date?
    }

    private let api: any PlaybackReportingAPI
    private let journal: ReportJournal
    private let owner: String
    private let connectivity: any ReportingConnectivity
    private let effects: any PlaybackEffects
    private let progressInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var active: Active?
    private var isDraining = false

    /// `owner` is `Session.libraryOwner`: the journal is only replayed for the user who wrote it.
    public init(
        api: any PlaybackReportingAPI, storage: any ReportJournalStorage, owner: String,
        connectivity: any ReportingConnectivity, effects: any PlaybackEffects,
        progressInterval: TimeInterval = PlaybackReporter.defaultProgressInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.journal = ReportJournal(storage: storage)
        self.owner = owner
        self.connectivity = connectivity
        self.effects = effects
        self.progressInterval = progressInterval
        self.now = now
    }

    // MARK: Playback lifecycle

    /// A new playback is about to run (a replay after an error is a new `PlaySessionId`). Reports nothing yet.
    public func begin(_ identity: PlaybackIdentity) {
        active = Active(identity: identity)
    }

    /// The first `playing` event, not the opening of the screen. Once per playback.
    public func started(_ snapshot: PlaybackSnapshot) async {
        guard var current = active, !current.started else { return }
        current.started = true
        current.lastSentAt = now()
        active = current
        journal.record(owner: owner, kind: .start, payload: payload(current.identity, snapshot))
        await drain()
    }

    public func update(_ snapshot: PlaybackSnapshot, trigger: ProgressTrigger = .timeUpdate) async {
        guard var current = active, current.started else { return }
        let date = now()
        if trigger == .timeUpdate, let last = current.lastSentAt, date.timeIntervalSince(last) < progressInterval { return }
        current.lastSentAt = date
        active = current
        journal.record(owner: owner, kind: .progress, payload: payload(current.identity, snapshot))
        await drain()
    }

    /// End of file, leaving the player or closing the app. Nothing is written if playback never started
    /// (a player opened then left before the first frame).
    public func stop(_ snapshot: PlaybackSnapshot) async {
        guard let current = active else { return }
        active = nil
        guard current.started else { return }
        await effects.playbackStopped(itemId: current.identity.itemId, positionTicks: snapshot.positionTicks)
        journal.record(owner: owner, kind: .stopped, payload: payload(current.identity, snapshot))
        await drain()
    }

    // MARK: Drain

    /// Sends the journal, oldest first. Call on return to `online`, at session launch and after a playback.
    /// One pass at a time. Stops at the first failure: no hammering, the next trigger retries.
    public func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while let report = journal.next(owner: owner) {
            guard await connectivity.isOnline() else { return }
            do {
                try await send(report)
            } catch let error where Self.isPermanentRefusal(error) {
                // The item is gone or the report malformed: it will never be accepted. Dropped.
            } catch {
                await connectivity.reportFailure(error)
                return
            }
            journal.complete(report)
            await connectivity.reportSuccess()
            if report.kind == .stopped { await effects.stopReportAccepted(itemId: report.payload.itemId) }
        }
    }

    private func send(_ report: PendingReport) async throws {
        switch report.kind {
        case .start: try await api.reportStart(report.payload.stateInfo)
        case .progress: try await api.reportProgress(report.payload.stateInfo)
        case .stopped: try await api.reportStopped(report.payload.stopInfo)
        }
    }

    /// 400/404: never acceptable. Anything else (401 included, which the client already signalled) is retried later.
    private static func isPermanentRefusal(_ error: any Error) -> Bool {
        if case JellyfinError.http(let code) = error { return code == 400 || code == 404 }
        return false
    }

    private func payload(_ identity: PlaybackIdentity, _ snapshot: PlaybackSnapshot) -> ReportPayload {
        ReportPayload(
            itemId: identity.itemId, mediaSourceId: identity.mediaSourceId, playSessionId: identity.playSessionId,
            playMethod: identity.playMethod, positionTicks: snapshot.positionTicks, isPaused: snapshot.isPaused,
            audioStreamIndex: snapshot.audioStreamIndex, subtitleStreamIndex: snapshot.subtitleStreamIndex
        )
    }

    // MARK: Diagnostics

    func pendingKinds() -> [[ReportKind]] { journal.pendingKinds(owner: owner) }
}
