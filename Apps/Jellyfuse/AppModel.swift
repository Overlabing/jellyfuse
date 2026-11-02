import Foundation
import HomePresentation
import LibraryKit
import Observation

/// Session lifecycle and the objects that live exactly as long as a session.
@MainActor
@Observable
final class AppModel {
    private(set) var session: Session?
    private(set) var home: HomeModel?
    /// What the player screen is showing, if anything.
    var playing: PlayRequest?

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
        playing = nil
    }

    func play(_ target: PlayTarget) {
        guard let home, let url = home.streamURL(for: target) else { return }
        playing = PlayRequest(url: url, startSeconds: target.resumeSeconds)
    }

    private func start(_ session: Session) {
        self.session = session
        let client = JellyfinClient(session: session, onUnauthorized: Self.makeUnauthorizedHandler(self))
        home = HomeModel(session: session, client: client)
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
    let url: URL
    let startSeconds: Double
}
