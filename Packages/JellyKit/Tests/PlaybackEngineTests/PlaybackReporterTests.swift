import Foundation
import JellyfinAPI
import LibraryKit
import Testing
@testable import PlaybackEngine

enum SentReport: Equatable {
    case start(PlaybackStateInfo)
    case progress(PlaybackStateInfo)
    case stopped(PlaybackStopInfo)

    var kind: String {
        switch self {
        case .start: "start"
        case .progress: "progress"
        case .stopped: "stopped"
        }
    }
}

/// Scripted `PlaybackReportingAPI`: records every attempt, fails with queued errors first.
actor FakeReportingAPI: PlaybackReportingAPI {
    private(set) var attempts: [SentReport] = []
    private(set) var accepted: [SentReport] = []
    private var errors: [any Error] = []

    func queueErrors(_ list: [any Error]) { errors = list }

    private func handle(_ report: SentReport) throws {
        attempts.append(report)
        if !errors.isEmpty { throw errors.removeFirst() }
        accepted.append(report)
    }

    func reportStart(_ info: PlaybackStateInfo) async throws { try handle(.start(info)) }
    func reportProgress(_ info: PlaybackStateInfo) async throws { try handle(.progress(info)) }
    func reportStopped(_ info: PlaybackStopInfo) async throws { try handle(.stopped(info)) }
}

actor FakeConnectivity: ReportingConnectivity {
    var online = true
    private(set) var failures = 0
    func setOnline(_ value: Bool) { online = value }
    func isOnline() async -> Bool { online }
    func reportFailure(_ error: any Error) async { failures += 1 }
    func reportSuccess() async {}
}

actor FakeEffects: PlaybackEffects {
    private(set) var events: [String] = []
    func playbackStopped(itemId: String, positionTicks: Int64) async { events.append("local:\(itemId):\(positionTicks)") }
    func stopReportAccepted(itemId: String) async { events.append("accepted:\(itemId)") }
}

@Suite struct PlaybackReporterTests {
    private let api = FakeReportingAPI()
    private let connectivity = FakeConnectivity()
    private let effects = FakeEffects()
    private let storage = MemoryStorage()
    private let clock = Clock()

    private func identity(item: String = "item1", source: String = "src1", session: String = "ps1") -> PlaybackIdentity {
        PlaybackIdentity(itemId: item, mediaSourceId: source, playSessionId: session, playMethod: .directPlay)
    }

    private func makeReporter(owner: String = "srv|u1", storage: MemoryStorage? = nil) -> PlaybackReporter {
        PlaybackReporter(
            api: api, storage: storage ?? self.storage, owner: owner, connectivity: connectivity, effects: effects,
            now: { [clock] in clock.now }
        )
    }

    private func snap(_ seconds: Int, paused: Bool = false, audio: Int? = 1, subtitle: Int? = -1) -> PlaybackSnapshot {
        PlaybackSnapshot(positionTicks: Int64(seconds) * 10_000_000, isPaused: paused, audioStreamIndex: audio, subtitleStreamIndex: subtitle)
    }

    // MARK: Sequence and fields

    @Test func startProgressStoppedSequenceWithExactFields() async throws {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        clock.advance(10)
        await reporter.update(snap(10, audio: 2, subtitle: 4))
        await reporter.stop(snap(42, audio: 2, subtitle: 4))

        let sent = await api.accepted
        #expect(sent.map(\.kind) == ["start", "progress", "stopped"])
        guard case .start(let start) = sent[0], case .progress(let progress) = sent[1], case .stopped(let stopped) = sent[2] else {
            Issue.record("unexpected report shapes")
            return
        }
        #expect(start.itemID == "item1" && start.mediaSourceID == "src1" && start.playSessionID == "ps1")
        #expect(start.itemID != start.mediaSourceID)
        #expect(start.positionTicks == 0 && start.playMethod == .directPlay && start.canSeek == true && start.isPaused == false)
        #expect(start.audioStreamIndex == 1 && start.subtitleStreamIndex == -1)
        #expect(progress.itemID == "item1" && progress.positionTicks == 100_000_000)
        #expect(progress.audioStreamIndex == 2 && progress.subtitleStreamIndex == 4)
        #expect(stopped.itemID == "item1" && stopped.mediaSourceID == "src1" && stopped.playSessionID == "ps1")
        #expect(stopped.positionTicks == 420_000_000)
    }

    @Test func chainingEpisodesStopsTheCurrentOneBeforeTheNextOneStarts() async {
        let reporter = makeReporter()
        await reporter.begin(identity(item: "ep1", session: "ps1"))
        await reporter.started(snap(0))
        await reporter.stop(snap(1500))
        await reporter.begin(identity(item: "ep2", session: "ps2"))
        await reporter.started(snap(0))

        let sent = await api.accepted
        #expect(sent.map(\.kind) == ["start", "stopped", "start"])
        guard case .stopped(let stopped) = sent[1], case .start(let start) = sent[2] else {
            Issue.record("unexpected report shapes")
            return
        }
        #expect(stopped.itemID == "ep1" && stopped.positionTicks == 15_000_000_000)
        #expect(start.itemID == "ep2" && start.playSessionID == "ps2" && start.positionTicks == 0)
    }

    @Test func itemIdIsNeverTheMediaSourceIdOnTheWire() async throws {
        let reporter = makeReporter()
        await reporter.begin(identity(item: "ITEM", source: "SOURCE"))
        await reporter.started(snap(0))
        await reporter.stop(snap(5))
        for report in await api.accepted {
            switch report {
            case .start(let info), .progress(let info):
                #expect(info.itemID == "ITEM" && info.mediaSourceID == "SOURCE")
            case .stopped(let info):
                #expect(info.itemID == "ITEM" && info.mediaSourceID == "SOURCE")
            }
        }
    }

    @Test func noEventNameOnTheWire() throws {
        let payload = ReportPayload(
            itemId: "i", mediaSourceId: "m", playSessionId: "p", playMethod: .directPlay,
            positionTicks: 1, isPaused: false, audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        let json = try String(decoding: JSONEncoder().encode(payload.stateInfo), as: UTF8.self)
        #expect(json.contains("\"ItemId\":\"i\"") && json.contains("\"MediaSourceId\":\"m\""))
        #expect(!json.contains("EventName"))
        let stop = try String(decoding: JSONEncoder().encode(payload.stopInfo), as: UTF8.self)
        #expect(!stop.contains("AudioStreamIndex") && !stop.contains("SubtitleStreamIndex") && !stop.contains("EventName"))
    }

    @Test func timeUpdatesAreThrottledToTenSecondsImmediateEventsAreNot() async {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        clock.advance(4)
        await reporter.update(snap(4))
        clock.advance(4)
        await reporter.update(snap(8))
        #expect(await api.accepted.map(\.kind) == ["start"])
        clock.advance(2)
        await reporter.update(snap(10))
        #expect(await api.accepted.map(\.kind) == ["start", "progress"])
        clock.advance(1)
        await reporter.update(snap(11, paused: true), trigger: .immediate)
        let sent = await api.accepted
        #expect(sent.map(\.kind) == ["start", "progress", "progress"])
        guard case .progress(let pause) = sent[2] else { return }
        #expect(pause.isPaused == true && pause.positionTicks == 110_000_000)
    }

    @Test func updatesBeforeStartAreIgnored() async {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.update(snap(3), trigger: .immediate)
        #expect(await api.attempts.isEmpty)
    }

    @Test func stopBeforeTheFirstPlayingWritesNothing() async {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.stop(snap(0))
        #expect(await api.attempts.isEmpty)
        #expect(await effects.events.isEmpty)
        #expect(await reporter.pendingKinds().isEmpty)
    }

    @Test func startIsSentOnlyOnce() async {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await reporter.started(snap(1))
        #expect(await api.accepted.map(\.kind) == ["start"])
    }

    // MARK: Journal

    @Test func offlineCoalescesToStartLastProgressAndStopped() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        for step in 1...200 {
            clock.advance(11)
            await reporter.update(snap(step * 11))
        }
        #expect(await reporter.pendingKinds() == [[.start, .progress]])
        await reporter.stop(snap(2300))
        // The Progress is superseded by the Stopped of its session: gone from the journal at once.
        #expect(await reporter.pendingKinds() == [[.start, .stopped]])
        #expect(await api.attempts.isEmpty)

        await connectivity.setOnline(true)
        await reporter.drain()
        #expect(await api.accepted.map(\.kind) == ["start", "stopped"])
        #expect(await reporter.pendingKinds().isEmpty)
    }

    @Test func offlineProgressKeepsOnlyTheLastOne() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        clock.advance(11)
        await reporter.update(snap(11))
        clock.advance(11)
        await reporter.update(snap(22))
        await connectivity.setOnline(true)
        await reporter.drain()
        let sent = await api.accepted
        #expect(sent.map(\.kind) == ["start", "progress"])
        guard case .progress(let last) = sent[1] else { return }
        #expect(last.positionTicks == 220_000_000)
    }

    @Test func anEntryLeavesTheJournalOnlyAfterServerAcceptance() async {
        await api.queueErrors([URLError(.notConnectedToInternet)])
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        #expect(await api.attempts.count == 1)
        #expect(await api.accepted.isEmpty)
        #expect(await reporter.pendingKinds() == [[.start]])
        #expect(await connectivity.failures == 1)
        await reporter.drain()
        #expect(await api.accepted.map(\.kind) == ["start"])
        #expect(await reporter.pendingKinds().isEmpty)
    }

    @Test func journalSurvivesARelaunch() async {
        await connectivity.setOnline(false)
        let first = makeReporter()
        await first.begin(identity())
        await first.started(snap(0))
        await first.stop(snap(30))

        await connectivity.setOnline(true)
        let relaunched = makeReporter()
        #expect(await relaunched.pendingKinds() == [[.start, .stopped]])
        await relaunched.drain()
        #expect(await api.accepted.map(\.kind) == ["start", "stopped"])
        #expect(await relaunched.pendingKinds().isEmpty)
    }

    @Test func drainStopsAtTheFirstFailureAndKeepsTheRest() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        for session in ["ps1", "ps2", "ps3"] {
            await reporter.begin(identity(session: session))
            await reporter.started(snap(0))
            await reporter.stop(snap(30))
        }
        await connectivity.setOnline(true)
        await api.queueErrors([URLError(.timedOut)])
        await reporter.drain()
        // One attempt, one failure: nothing hammered, everything kept.
        #expect(await api.attempts.count == 1)
        #expect(await reporter.pendingKinds().count == 3)

        await reporter.drain()
        #expect(await api.accepted.count == 6)
        #expect(await reporter.pendingKinds().isEmpty)
        // Oldest session first.
        let order = await api.accepted.compactMap { report -> String? in
            switch report {
            case .start(let info): info.playSessionID
            case .stopped(let info): info.playSessionID
            case .progress: nil
            }
        }
        #expect(order == ["ps1", "ps1", "ps2", "ps2", "ps3", "ps3"])
    }

    @Test func serverErrorStopsThePassToo() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await reporter.stop(snap(30))
        await connectivity.setOnline(true)
        await api.queueErrors([JellyfinError.http(503)])
        await reporter.drain()
        #expect(await api.attempts.count == 1)
        #expect(await reporter.pendingKinds() == [[.start, .stopped]])
    }

    @Test func unauthorizedStopsThePassAndKeepsTheJournal() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await reporter.stop(snap(30))
        await connectivity.setOnline(true)
        await api.queueErrors([JellyfinError.unauthorized])
        await reporter.drain()
        #expect(await api.attempts.count == 1)
        #expect(await reporter.pendingKinds() == [[.start, .stopped]])
    }

    @Test func goneItemsAreDroppedAndTheDrainContinues() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        for session in ["ps1", "ps2"] {
            await reporter.begin(identity(session: session))
            await reporter.started(snap(0))
            await reporter.stop(snap(30))
        }
        await connectivity.setOnline(true)
        // ps1's Start and Stopped are refused for good (item deleted); ps2 goes through.
        await api.queueErrors([JellyfinError.http(404), JellyfinError.http(400)])
        await reporter.drain()
        #expect(await api.attempts.count == 4)
        #expect(await api.accepted.count == 2)
        #expect(await reporter.pendingKinds().isEmpty)
    }

    @Test func offlineDrainDoesNotTouchTheNetwork() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await reporter.drain()
        #expect(await api.attempts.isEmpty)
        #expect(await reporter.pendingKinds() == [[.start]])
    }

    @Test func onlyTheOwnersEntriesAreReplayed() async {
        await connectivity.setOnline(false)
        let alice = makeReporter(owner: "srv|alice")
        await alice.begin(identity(session: "alice-ps"))
        await alice.started(snap(0))

        await connectivity.setOnline(true)
        let bob = makeReporter(owner: "srv|bob")
        await bob.drain()
        #expect(await api.attempts.isEmpty)
        #expect(await bob.pendingKinds().isEmpty)

        let aliceAgain = makeReporter(owner: "srv|alice")
        await aliceAgain.drain()
        #expect(await api.accepted.count == 1)
    }

    // MARK: Local effects

    @Test func stopPatchesLocalStateImmediatelyAndInvalidatesOnlyAfterAcceptance() async {
        await connectivity.setOnline(false)
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await reporter.stop(snap(30))
        #expect(await effects.events == ["local:item1:300000000"])

        await connectivity.setOnline(true)
        await reporter.drain()
        #expect(await effects.events == ["local:item1:300000000", "accepted:item1"])
    }

    @Test func aRefusedStopDoesNotInvalidate() async {
        let reporter = makeReporter()
        await reporter.begin(identity())
        await reporter.started(snap(0))
        await api.queueErrors([URLError(.timedOut)])
        await reporter.stop(snap(30))
        #expect(await effects.events == ["local:item1:300000000"])
    }
}

@Suite struct ReportJournalTests {
    private func payload(_ session: String, position: Int64 = 0) -> ReportPayload {
        ReportPayload(
            itemId: "i", mediaSourceId: "m", playSessionId: session, playMethod: .directPlay,
            positionTicks: position, isPaused: false, audioStreamIndex: nil, subtitleStreamIndex: nil
        )
    }

    @Test func capsTheJournalAtFiftySessionsDroppingTheOldest() {
        let journal = ReportJournal(storage: MemoryStorage())
        for number in 0..<60 { journal.record(owner: "o", kind: .start, payload: payload("ps\(number)")) }
        let kinds = journal.pendingKinds(owner: "o")
        #expect(kinds.count == 50)
        #expect(journal.next(owner: "o")?.playSessionId == "ps10")
    }

    @Test func aNewerReportInTheSameSlotSurvivesTheCompletionOfTheOlderOne() throws {
        let journal = ReportJournal(storage: MemoryStorage())
        journal.record(owner: "o", kind: .progress, payload: payload("ps", position: 1))
        let inFlight = try #require(journal.next(owner: "o"))
        journal.record(owner: "o", kind: .progress, payload: payload("ps", position: 2))
        journal.complete(inFlight)
        #expect(journal.next(owner: "o")?.payload.positionTicks == 2)
    }

    @Test func aProgressAfterTheStoppedOfTheSameSessionIsIgnored() {
        let journal = ReportJournal(storage: MemoryStorage())
        journal.record(owner: "o", kind: .stopped, payload: payload("ps"))
        journal.record(owner: "o", kind: .progress, payload: payload("ps"))
        #expect(journal.pendingKinds(owner: "o") == [[.stopped]])
    }

    @Test func anUnreadableJournalIsDiscardedNotFatal() {
        let storage = MemoryStorage()
        try? storage.save(Data("not json".utf8))
        let journal = ReportJournal(storage: storage)
        #expect(journal.next(owner: "o") == nil)
        journal.record(owner: "o", kind: .start, payload: payload("ps"))
        #expect(journal.pendingKinds(owner: "o") == [[.start]])
    }
}
/// Thread-safe in-memory journal storage, shareable between two reporters to simulate a relaunch.
final class MemoryStorage: ReportJournalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func load() throws -> Data? { lock.withLock { data } }
    func save(_ data: Data) throws { lock.withLock { self.data = data } }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
