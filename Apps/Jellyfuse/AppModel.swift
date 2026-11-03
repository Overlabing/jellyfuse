import Foundation
import HomePresentation
import LibraryKit
import Observation
#if !PLAYER_DISABLED
import PlaybackEngine
#endif

/// Session lifecycle and the objects that live exactly as long as a session.
@MainActor
@Observable
final class AppModel {
    private(set) var session: Session?
    private(set) var home: HomeModel?
    #if !PLAYER_DISABLED
    private(set) var playback: PlaybackServices?
    #endif
    /// What the player screen is showing, if anything.
    var playing: PlayRequest?
    /// The « Reprendre / Recommencer » question, when a playback with a saved position was requested.
    var resumePrompt: PlayPrompt?

    /// A `jellyfuse://` link waiting for the main screen: it can arrive before the session is loaded
    /// (cold start) or before sign-in. The main tabs consume it.
    var pendingLink: DeepLink?

    init() {
        SessionStore.accessGroup = Self.sharedKeychainGroup
        if let stored = SessionStore.load() {
            // Re-saved into the shared group: a session stored before the Top Shelf extension existed moves there.
            try? SessionStore.save(stored)
            start(stored)
        }
    }

    /// `$(AppIdentifierPrefix)com.jellyfusion.app.shared`, shared with the Top Shelf extension.
    static let sharedKeychainGroup = "39TMVBW2CY.com.jellyfusion.app.shared"

    func open(_ url: URL) {
        pendingLink = DeepLink(url: url)
    }

    func signedIn(_ session: Session) {
        try? SessionStore.save(session)
        start(session)
    }

    func signOut() {
        SessionStore.clear()
        session = nil
        home = nil
        #if !PLAYER_DISABLED
        playback = nil
        #endif
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
        #if !PLAYER_DISABLED
        playback = PlaybackServices(session: session, client: client, store: home.store, reachability: home.reachability)
        #endif
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
