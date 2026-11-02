import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer: wires `HomeModel` to the pure `HomeView`. « Voir tout » pushes the library grid
/// on this tab's own stack: the Menu button pops it.
struct HomeScreen: View {
    let model: HomeModel
    let onPlay: (PlayTarget) -> Void
    @State private var path: [Library] = []

    var body: some View {
        NavigationStack(path: $path) {
            let content = model.content
            HomeView(
                content: content,
                isLoadingCold: model.isLoadingCold,
                failureMessage: model.failure.map(Self.message),
                onPlay: { id in
                    if let target = content.target(for: id) { onPlay(target) }
                },
                onSeeAll: { path.append($0) },
                // Favorites need a façade mutation (lot 3.3, optimistic patch): not wired yet.
                onToggleList: {}
            )
            .navigationDestination(for: Library.self) { library in
                RecentGridScreen(model: model, library: library, onPlay: onPlay)
            }
        }
        .task { await model.refresh() }
    }

    private static func message(for failure: UserFacingError) -> String {
        switch failure {
        case .network: String(localized: "Serveur injoignable.")
        case .unauthorized: String(localized: "Session expirée.")
        case .server, .unreadable, .other: String(localized: "Impossible de charger l'accueil.")
        }
    }
}
