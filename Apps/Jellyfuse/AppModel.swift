import Foundation
import HomePresentation
import LibraryKit
import Observation
import PlaybackEngine

/// Session lifecycle and the objects that live exactly as long as a session.
@MainActor
@Observable
final class AppModel {
    private(set) var session: Session?
    private(set) var home: HomeModel?
    private(set) var playback: PlaybackServices?
    /// What the player screen is showing, if anything.
    var playing: PlayRequest?
    /// The « Reprendre / Recommencer » question, when a playback with a saved position was requested.
    var resumePrompt: PlayPrompt?

    init() {
        if let stored = SessionStore.load() { start(stored) }
    }

    func signedIn(_ session: Session) {
        try? SessionStore.save(session)
        start(session)
    }

    func signOut() {
        SessionStore.clear()
        session = nil
        home = nil
        playback = nil
        playing = nil
        resumePrompt = nil
    }

    /// Single entry point for every playback: a saved position asks first, otherwise it starts at once.
    func play(_ target: PlayTarget) {
        if let prompt = PlayPrompt(target) { resumePrompt = prompt } else { start(playing: target) }
    }

    /// The answer to the prompt (`prompt.resume` or `prompt.restart`).
    func choose(_ target: PlayTarget) {
        resumePrompt = nil
        start(playing: target)
    }

    private func start(playing target: PlayTarget) {
        playing = PlayRequest(target: target)
    }

    private func start(_ session: Session) {
        self.session = session
        let client = JellyfinClient(session: session, onUnauthorized: Self.makeUnauthorizedHandler(self))
        let home = HomeModel(session: session, client: client)
        self.home = home
        playback = PlaybackServices(session: session, client: client, store: home.store, reachability: home.reachability)
    }

    /// Fired from the SDK's threads: built outside the actor so the closure does not inherit its isolation.
    private nonisolated static func makeUnauthorizedHandler(_ model: AppModel) -> @Sendable () -> Void {
        { @Sendable [weak model] in
            Task { @MainActor in model?.signOut() }
        }
    }
}

struct PlayRequest: Identifiable, Equatable {
    let id = UUID()
    let target: PlayTarget
}
