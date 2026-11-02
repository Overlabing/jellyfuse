import Foundation
import Observation
import PlayerCore

/// Plays one stream and mirrors the player's events into observable state.
@MainActor
@Observable
final class PlaybackModel {
    private(set) var state = "loading"
    private(set) var timePosition = 0.0
    private(set) var duration = 0.0
    private(set) var videoCodec = "-"
    private(set) var hwdecCurrent = "-"
    private(set) var lastError: String?
    private(set) var failure: String?

    let player: MpvPlayer?
    private var eventTask: Task<Void, Never>?

    private let startSeconds: Double

    init(startSeconds: Double = 0) {
        self.startSeconds = startSeconds
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
            failure = String(describing: error)
        }
        guard let player else { return }
        eventTask = Task { [weak self] in
            for await event in player.events {
                self?.apply(event)
            }
        }
    }

    isolated deinit {
        eventTask?.cancel()
        player?.shutdown()
    }

    func togglePause() { player?.togglePause() }

    private func apply(_ event: MpvEvent) {
        switch event {
        case .startFile: state = "loading"
        case .fileLoaded:
            state = "playing"
            if startSeconds > 0 { player?.seek(to: startSeconds) }
        case .endFile(let error):
            state = error == nil ? "ended" : "error"
            lastError = error
        case .shutdown: state = "stopped"
        case .propertyChanged(let property):
            switch property {
            case .timePosition(let value): timePosition = value
            case .duration(let value): duration = value
            case .paused(let paused): if state == "playing" || state == "paused" { state = paused ? "paused" : "playing" }
            case .videoCodec(let value): videoCodec = value
            case .hwdecCurrent(let value): hwdecCurrent = value.isEmpty ? "(none)" : value
            case .pausedForCache, .videoConfigured: break
            }
        }
    }
}
