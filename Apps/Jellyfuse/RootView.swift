import DesignSystem
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

    var body: some View {
        TabView {
            HomeScreen(model: home, onPlay: { model.play($0) })
                .tabItem { Text("Accueil") }
            PlaceholderScreen(title: String(localized: "Films"))
                .tabItem { Text("Films") }
            PlaceholderScreen(title: String(localized: "Séries"))
                .tabItem { Text("Séries") }
            PlaceholderScreen(title: String(localized: "Recherche"))
                .tabItem { Text("Recherche") }
            PlaceholderScreen(title: String(localized: "Réglages"))
                .tabItem { Text("Réglages") }
        }
        .fullScreenCover(item: $model.playing) { request in
            PlayerScreen(target: request.target, services: playback, onClose: { model.playing = nil })
        }
    }
}
