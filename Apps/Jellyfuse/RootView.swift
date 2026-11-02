import DesignSystem
import HomePresentation
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeScreen(model: home, isPlayerOpen: model.playing != nil, onPlay: { model.play($0) })
                .tabItem { Text("Accueil") }
            PlaceholderScreen(title: String(localized: "Films"))
                .tabItem { Text("Films") }
            PlaceholderScreen(title: String(localized: "Séries"))
                .tabItem { Text("Séries") }
            SearchScreen(home: home, onPlay: { model.play($0) })
                .tabItem { Text("Recherche") }
            SettingsScreen(session: model.session, playback: playback, onSignOut: { model.signOut() })
                .tabItem { Text("Réglages") }
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
