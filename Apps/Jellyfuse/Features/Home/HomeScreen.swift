import HomePresentation
import SwiftUI
import LibraryKit

/// Composition layer: wires `HomeModel` to the pure `HomeView`.
struct HomeScreen: View {
    let model: HomeModel
    let onPlay: (PlayTarget) -> Void

    var body: some View {
        let content = model.content
        HomeView(
            content: content,
            isLoadingCold: model.isLoadingCold,
            failureMessage: model.failure.map(Self.message),
            onPlay: { id in
                if let target = content.target(for: id) { onPlay(target) }
            },
            // Favorites need a façade mutation (lot 3.3, optimistic patch): not wired yet.
            onToggleList: {}
        )
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
