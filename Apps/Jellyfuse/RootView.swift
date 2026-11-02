import DesignSystem
import HomePresentation
import LibraryKit
import SwiftUI

/// Session gate: sign-in until there is a session, then the native tab bar.
struct RootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Design.Palette.canvas.ignoresSafeArea()
            if let home = model.home, let playback = model.playback {
                MainTabs(model: model, home: home, playback: playback)
            } else {
                LoginScreen(onSignedIn: { model.signedIn($0) })
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MainTabs: View {
    @Bindable var model: AppModel
    let home: HomeModel
    let playback: PlaybackServices
    @State private var selection = Tab.home
    /// A detail screen a deep link asked the home stack to open.
    @State private var detailRequest: String?
    @Environment(\.scenePhase) private var scenePhase

    private enum Tab { case home, movies, shows, search, settings }

    var body: some View {
        TabView(selection: $selection) {
            HomeScreen(model: home, isPlayerOpen: model.playing != nil, detailRequest: $detailRequest, onPlay: { model.play($0) })
                .tabItem { Text("Accueil") }
                .tag(Tab.home)
            LibraryScreen(home: home, kind: .movies, onPlay: { model.play($0) })
                .tabItem { Text("Films") }
                .tag(Tab.movies)
            LibraryScreen(home: home, kind: .tvshows, onPlay: { model.play($0) })
                .tabItem { Text("Séries") }
                .tag(Tab.shows)
            SearchScreen(home: home, onPlay: { model.play($0) })
                .tabItem { Text("Recherche") }
                .tag(Tab.search)
            SettingsScreen(session: model.session, playback: playback, onSignOut: { model.signOut() })
                .tabItem { Text("Réglages") }
                .tag(Tab.settings)
        }
        .onChange(of: model.pendingLink, initial: true) { _, link in
            guard let link else { return }
            model.pendingLink = nil
            switch link {
            case .detail(let id):
                selection = .home
                detailRequest = id
            case .play(let id, let title, let seconds):
                model.play(PlayTarget(id: id, title: title, resumeSeconds: seconds))
            }
        }
        .confirmationDialog(
            model.resumePrompt?.title ?? "",
            isPresented: Binding(get: { model.resumePrompt != nil }, set: { if !$0 { model.resumePrompt = nil } }),
            titleVisibility: .visible,
            presenting: model.resumePrompt
        ) { prompt in
            Button(prompt.resumeLabel) { model.choose(prompt.resume) }
            Button("Recommencer depuis le début") { model.choose(prompt.restart) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground: stale shelves reload, and reports a previous run could not send are retried.
            guard phase == .active else { return }
            Task {
                await home.refresh()
                await playback.reporter.drain()
            }
        }
        .fullScreenCover(item: $model.playing) { request in
            // `.id`: the next episode replaces the request, and the new player must not inherit the old one's state.
            PlayerScreen(
                target: request.target, services: playback, onClose: { model.playing = nil }, onPlayNext: { model.play($0) }
            )
            .id(request.id)
        }
    }
}
