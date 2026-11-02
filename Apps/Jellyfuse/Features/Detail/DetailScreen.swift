import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer: wires `DetailModel` to the pure `DetailView`. Lecture and episodes hand a
/// `PlayTarget` to the player flow.
struct DetailScreen: View {
    let model: DetailModel
    let onPlay: (PlayTarget) -> Void

    var body: some View {
        let content = model.content
        DetailView(
            content: content,
            isLoadingChildren: model.isLoadingChildren,
            failureMessage: model.failure.map(Self.message),
            favoriteFailureMessage: model.favoriteFailed ? String(localized: "Impossible de modifier Ma liste.") : nil,
            onPlay: {
                if let target = content?.playTarget { onPlay(target) }
            },
            onToggleFavorite: { Task { await model.toggleFavorite() } },
            onSelectSeason: { model.selectedSeasonId = $0 },
            onPlayEpisode: { id in
                if let target = content?.target(forEpisode: id) { onPlay(target) }
            }
        )
        .task { await model.refresh() }
    }

    private static func message(for failure: UserFacingError) -> String {
        switch failure {
        case .network: String(localized: "Serveur injoignable.")
        case .unauthorized: String(localized: "Session expirée.")
        case .server, .unreadable, .other: String(localized: "Impossible de charger la fiche.")
        }
    }
}
