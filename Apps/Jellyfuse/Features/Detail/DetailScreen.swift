import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer: wires `DetailModel` to the pure `DetailView`. Lecture and episodes hand a
/// `PlayTarget` to the player flow.
struct DetailScreen: View {
    let model: DetailModel
    let onPlay: (PlayTarget) -> Void
    /// `(personId, name)`: a cast card was selected.
    let onOpenPerson: (String, String) -> Void

    var body: some View {
        let content = model.content
        DetailView(
            content: content,
            isLoadingChildren: model.isLoadingChildren,
            failureMessage: model.failure.map(Self.message),
            actionFailureMessage: model.actionFailure.map(Self.message),
            onPlay: {
                if let target = content?.playTarget { onPlay(target) }
            },
            onToggleFavorite: { Task { await model.toggleFavorite() } },
            onToggleWatched: { Task { await model.toggleWatched() } },
            onSelectSeason: { model.selectedSeasonId = $0 },
            onPlayEpisode: { id in
                if let target = content?.target(forEpisode: id) { onPlay(target) }
            },
            onSetEpisodeWatched: { id, watched in Task { await model.setWatched(watched, for: id) } },
            onOpenPerson: { onOpenPerson($0.personId, $0.name) }
        )
        .task { await model.refresh() }
    }

    private static func message(for failure: DetailModel.ActionFailure) -> String {
        switch failure {
        case .favorite: String(localized: "Impossible de modifier Ma liste.")
        case .watched: String(localized: "Impossible de modifier l'état « vu ».")
        }
    }

    private static func message(for failure: UserFacingError) -> String {
        switch failure {
        case .network: String(localized: "Serveur injoignable.")
        case .unauthorized: String(localized: "Session expirée.")
        case .server, .unreadable, .other: String(localized: "Impossible de charger la fiche.")
        }
    }
}
