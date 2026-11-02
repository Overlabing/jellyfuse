import Foundation
import DesignSystem
import HomePresentation
import LibraryKit
import Observation
import PlaybackEngine
import PlayerCore
import PlayerPresentation

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

    /// The audio and subtitle tracks that can be switched; empty when transcoding or before resolving.
    private(set) var catalog = TrackCatalog.empty
    /// Jellyfin indexes of the tracks playing; no subtitle index = off.
    private(set) var audioIndex: Int?
    private(set) var subtitleIndex: Int?
    /// Synopsis and chapters, once loaded.
    private(set) var detail: ItemDetail?
    /// The intro and credits the server marked, if any.
    private(set) var segments = ItemSegments.none
    /// The following episode, when this is an episode that has one.
    private(set) var nextEpisode: NextEpisode?
    /// Set when the countdown ran out: the screen then plays this episode.
    private(set) var autoplay: NextEpisode?
    private var endOfEpisode = EndOfEpisodeState()
    private var countdownElapsed = 0.0
    private var countdownTask: Task<Void, Never>?

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
    private var detailTask: Task<Void, Never>?
    private var extrasTask: Task<Void, Never>?
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
        let id = target.id
        detailTask = Task { [weak self] in
            let detail = await services.detail(id)
            self?.detail = detail
        }
        // One request each per playback, off the critical path of the stream.
        extrasTask = Task { [weak self] in
            async let segments = services.segments(id)
            async let next = services.nextEpisode(after: id)
            let (foundSegments, foundNext) = await (segments, next)
            guard !Task.isCancelled else { return }
            self?.segments = foundSegments
            self?.nextEpisode = foundNext
        }
    }

    isolated deinit {
        stop()
        resolveTask?.cancel()
        detailTask?.cancel()
        extrasTask?.cancel()
        countdownTask?.cancel()
        eventTask?.cancel()
        player?.shutdown()
    }

    /// Where the viewer is: a seek still in flight counts, so the bar and the reports do not lag behind it.
    var position: Double { seeks.position(playerPosition: timePosition, at: .now) }

    /// A requested jump is still in flight: the screen acknowledges it with an immediate loading hint.
    var isSeeking: Bool { seeks.isSettling(playerPosition: timePosition, at: .now) }

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

    // MARK: Segments and next episode

    /// The scrub thumbnails, when the server generated them.
    var trickplay: TrickplaySheet? { detail?.trickplay }

    /// The « Passer l'intro / le générique » segment the viewer is in.
    var skippableSegment: MediaSegment? { segments.skippable(at: position, hasNext: nextEpisode != nil) }

    func skipSegment() {
        guard let segment = skippableSegment else { return }
        seek(to: segment.end)
    }

    /// The end-of-episode card showing now, and the seconds left of its countdown.
    var endCard: (phase: EndOfEpisodePhase, countdown: Int)? {
        guard nextEpisode != nil, endOfEpisode.phase != .idle else { return nil }
        return (endOfEpisode.phase, max(Int((Double(EndOfEpisodeGate.countdownSeconds) - countdownElapsed).rounded(.up)), 0))
    }

    /// Menu on the card: « Regarder le générique » on the credits, a plain dismiss near the end. False when no
    /// card was showing, so Menu does its usual job.
    func dismissEndCard() -> Bool {
        guard endCard != nil else { return false }
        if endOfEpisode.phase == .credits { endOfEpisode.watchCredits() } else { endOfEpisode.dismiss() }
        cardChanged()
        return true
    }

    /// What plays when the file ends by itself: the next episode, unless the viewer turned its card down.
    var episodeAtEnd: NextEpisode? { endOfEpisode.isDismissed ? nil : nextEpisode }

    /// Runs the gate for a new position: re-arms after a backward seek, shows or clears the card.
    private func evaluateEnd(position: Double, previous: Double) {
        guard nextEpisode != nil else { return }
        if previous - position > EndOfEpisodeGate.rearmSeek { endOfEpisode.reset() }
        let credits = segments.credits.map { $0.start...$0.end }
        let target = EndOfEpisodeGate.targetPhase(position: position, duration: duration, credits: credits, hasNext: true)
        if target == .idle { endOfEpisode.complete() } else { endOfEpisode.enter(target) }
        cardChanged()
    }

    /// Starts the countdown when a card appears, stops it when it goes.
    private func cardChanged() {
        if endOfEpisode.phase == .idle {
            countdownTask?.cancel()
            countdownTask = nil
            countdownElapsed = 0
        } else if countdownTask == nil {
            countdownTask = Task { [weak self] in
                // Counts playing time only: a paused episode keeps its card.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, !Task.isCancelled else { return }
                    if self.isPaused { continue }
                    self.countdownElapsed += 0.25
                    if self.countdownElapsed >= Double(EndOfEpisodeGate.countdownSeconds) {
                        self.endOfEpisode.complete()
                        self.countdownTask = nil
                        self.countdownElapsed = 0
                        self.autoplay = self.nextEpisode
                        return
                    }
                }
            }
        }
    }

    // MARK: Tracks and chapters

    var chapters: [Chapter] { detail?.chapters ?? [] }

    /// Tracks can only be switched on a direct stream: a transcode carries the server's choice.
    var canSwitchTracks: Bool { resolved.map { $0.playMethod != .transcode } ?? false }

    /// The panel's content for the current state.
    func contentTabs() -> ContentTabsModel {
        ContentTabsMapper.model(.init(
            heading: heading, detail: detail, catalog: catalog, audioIndex: audioIndex, subtitleIndex: subtitleIndex,
            chapters: chapters, position: position, canSwitchTracks: canSwitchTracks
        ))
    }

    /// Switches audio now, remembers the language and tells the server.
    func selectAudio(_ index: Int) {
        guard let player, let resolved, let track = catalog.audioTrack(at: index) else { return }
        player.setTrack(.audio, id: track.mpvID)
        audioIndex = index
        services.trackPreferences.rememberAudio(
            .audio(resolved.streams.first { $0.index == index }), scope: services.trackScope(target.id)
        )
        reportTrackChange()
    }

    /// Switches the subtitles now (`nil` = off), remembers the choice and tells the server.
    func selectSubtitle(_ index: Int?) {
        guard let player, let resolved else { return }
        if let index {
            guard let track = catalog.subtitleTrack(at: index) else { return }
            player.setTrack(.subtitle, id: track.mpvID)
        } else {
            player.setTrack(.subtitle, id: nil)
        }
        subtitleIndex = index
        services.trackPreferences.rememberSubtitle(
            .subtitle(index.flatMap { index in resolved.streams.first { $0.index == index } }), scope: services.trackScope(target.id)
        )
        reportTrackChange()
    }

    private func reportTrackChange() {
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
            audioIndex = resolved.selection.audioIndex
            subtitleIndex = resolved.selection.subtitleIndex
            if resolved.playMethod != .transcode {
                catalog = TrackCatalog(streams: resolved.streams, externalIndices: resolved.externalSubtitles.map(\.index))
            }
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
            case .timePosition(let value):
                let previous = timePosition
                timePosition = value
                evaluateEnd(position: value, previous: previous)
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
            audioStreamIndex: audioIndex,
            // -1 is « subtitles off » for Jellyfin.
            subtitleStreamIndex: resolved == nil ? nil : (subtitleIndex ?? -1)
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
