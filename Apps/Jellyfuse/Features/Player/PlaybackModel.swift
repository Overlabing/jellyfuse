import Foundation
import DesignSystem
import HomePresentation
import LibraryKit
import Observation
import PlaybackEngine
import PlayerCore

/// Plays one item: resolves it, mirrors the player's events into observable state and reports the playback
/// (Start when it plays, Progress every ~10 s and on pause, Stopped once on exit).
@MainActor
@Observable
final class PlaybackModel {
    enum Phase: String {
        case loading, playing, paused, ended, error, stopped
    }

    private(set) var phase = Phase.loading
    private(set) var timePosition = 0.0
    private(set) var duration = 0.0
    private(set) var videoCodec = "-"
    private(set) var hwdecCurrent = "-"
    /// mpv's own error text, for the debug stats only.
    private(set) var lastError: String?
    /// Why nothing plays, in words for the viewer.
    private(set) var failure: String?
    private(set) var isPaused = false
    /// mpv is waiting for data.
    private(set) var isBuffering = false
    /// `Série › S1E4 · Titre`, or the film's title.
    let heading: String
    /// The stream to open, set once resolved. Carries the user's api_key: never log it.
    private(set) var streamURL: URL?

    let player: MpvPlayer?

    private enum Report: Sendable {
        case started(PlaybackSnapshot)
        case update(PlaybackSnapshot, ProgressTrigger)
        case stop(PlaybackSnapshot)
    }

    private let target: PlayTarget
    private let services: PlaybackServices
    private var resolved: ResolvedPlayback?
    private var eventTask: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private let reports: AsyncStream<Report>.Continuation
    private var hasStarted = false
    private var isStopped = false
    private var seeks = SeekTracker()

    init(target: PlayTarget, services: PlaybackServices) {
        self.target = target
        self.services = services
        heading = Self.heading(for: target, item: services.item(target.id))
        // Reports go through one ordered queue: separate Tasks could reorder Start/Progress/Stopped.
        let (stream, continuation) = AsyncStream.makeStream(of: Report.self)
        reports = continuation
        let reporter = services.reporter
        Task { await Self.pump(stream, into: reporter) }

        do {
            var options = MpvOptions()
            // Debug launch args (same as the spike): -mpvopt k=v,k=v and -start <secs>.
            if let raw = UserDefaults.standard.string(forKey: "mpvopt") {
                options.extraOptions = raw.split(separator: ",").map(String.init)
            }
            if let start = UserDefaults.standard.string(forKey: "start") {
                options.extraOptions.append("start=\(start)")
            }
            player = try MpvPlayer(options: options)
        } catch {
            player = nil
            failure = String(localized: "Le lecteur n'a pas pu démarrer.")
        }
        guard let player else { return }
        eventTask = Task { [weak self] in
            for await event in player.events {
                self?.apply(event)
            }
        }
        resolveTask = Task { [weak self] in await self?.resolve() }
    }

    isolated deinit {
        stop()
        resolveTask?.cancel()
        eventTask?.cancel()
        player?.shutdown()
    }

    /// Where the viewer is: a seek still in flight counts, so the bar and the reports do not lag behind it.
    var position: Double { seeks.position(playerPosition: timePosition, at: .now) }

    func setPaused(_ paused: Bool) {
        if paused { player?.pause() } else { player?.play() }
    }

    /// Seeks and reports the new position at once instead of waiting for the next tick.
    func seek(to seconds: Double) {
        guard let player else { return }
        seeks.seek(to: seconds, at: .now)
        player.seek(to: seconds)
        if hasStarted, !isStopped { reports.yield(.update(snapshot(), .immediate)) }
    }

    /// Reports Stopped with the final position. Idempotent: the screen disappearing, the end of the file and
    /// the deinit may all call it.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        tickTask?.cancel()
        reports.yield(.stop(snapshot()))
        reports.finish()
    }

    // MARK: Resolve

    private func resolve() async {
        do {
            let resolved = try await services.resolve(
                itemId: target.id, startPositionTicks: PlaybackSnapshot.ticks(seconds: target.resumeSeconds)
            )
            guard !Task.isCancelled, !isStopped else { return }
            self.resolved = resolved
            await services.reporter.begin(resolved.identity)
            streamURL = resolved.url
        } catch {
            guard !Task.isCancelled else { return }
            failure = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        switch UserFacingError(error) {
        case .network: String(localized: "Impossible de joindre le serveur.")
        case .unauthorized: String(localized: "Votre session a expiré.")
        case .server, .unreadable, .other: String(localized: "Ce contenu n'a pas pu être préparé pour la lecture.")
        }
    }

    private static func heading(for target: PlayTarget, item: MediaItem?) -> String {
        guard let item else { return target.title }
        return OSDModel.heading(
            name: item.name, seriesName: item.kind == .episode ? item.seriesName : nil,
            season: item.parentIndexNumber, episode: item.indexNumber
        )
    }

    // MARK: Events

    private func apply(_ event: MpvEvent) {
        switch event {
        case .startFile: phase = .loading
        case .fileLoaded: fileLoaded()
        case .endFile(let error):
            phase = error == nil ? .ended : .error
            lastError = error
            if error != nil { failure = String(localized: "Le fichier n'a pas pu être lu.") }
            stop()
        case .shutdown: phase = .stopped
        case .propertyChanged(let property):
            switch property {
            case .timePosition(let value): timePosition = value
            case .duration(let value): duration = value
            case .paused(let paused): pausedChanged(paused)
            case .videoCodec(let value): videoCodec = value
            case .hwdecCurrent(let value): hwdecCurrent = value.isEmpty ? "(none)" : value
            case .pausedForCache(let buffering): isBuffering = buffering
            case .videoConfigured: break
            }
        }
    }

    private func fileLoaded() {
        phase = isPaused ? .paused : .playing
        guard let player, let resolved else { return }
        if resolved.startPositionTicks > 0 {
            let start = Double(resolved.startPositionTicks) / Double(PlaybackSnapshot.ticksPerSecond)
            seeks.seek(to: start, at: .now)
            player.seek(to: start)
        }
        // Track ids only exist for a direct stream; a transcode already carries the server's choice.
        if resolved.playMethod != .transcode {
            for subtitle in resolved.externalSubtitles {
                player.addSubtitle(subtitle.url, title: subtitle.title, language: subtitle.language)
            }
            player.setTrack(.audio, id: resolved.audioID)
            player.setTrack(.subtitle, id: resolved.subtitleID)
        }
        guard !hasStarted else { return }
        hasStarted = true
        reports.yield(.started(snapshot()))
        tickTask = Task { [weak self] in
            // The reporter throttles `.timeUpdate` to its progress interval; a 1 s tick only samples the position.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.reports.yield(.update(self.snapshot(), .timeUpdate))
            }
        }
    }

    private func pausedChanged(_ paused: Bool) {
        isPaused = paused
        if phase == .playing || phase == .paused { phase = paused ? .paused : .playing }
        if hasStarted, !isStopped { reports.yield(.update(snapshot(), .immediate)) }
    }

    // MARK: Reporting

    private func snapshot() -> PlaybackSnapshot {
        PlaybackSnapshot(
            positionTicks: PlaybackSnapshot.ticks(seconds: position),
            isPaused: isPaused,
            audioStreamIndex: resolved?.selection.audioIndex,
            // -1 is « subtitles off » for Jellyfin.
            subtitleStreamIndex: resolved.map { $0.selection.subtitleIndex ?? -1 }
        )
    }

    /// Applies the queued reports in order. Outlives the model so a Stopped queued at exit still goes out.
    private nonisolated static func pump(_ stream: AsyncStream<Report>, into reporter: PlaybackReporter) async {
        for await report in stream {
            switch report {
            case .started(let snapshot): await reporter.started(snapshot)
            case .update(let snapshot, let trigger): await reporter.update(snapshot, trigger: trigger)
            case .stop(let snapshot): await reporter.stop(snapshot)
            }
        }
    }
}
