import HomePresentation
import LibraryKit
import SwiftUI

/// Where this tab's stack can go. Both destinations stay on the tab's own stack: Menu pops them.
enum HomeRoute: Hashable {
    case grid(Library)
    case detail(String)
}

/// Composition layer: wires `HomeModel` to the pure `HomeView`. « Voir tout » pushes the library grid,
/// a poster or the billboard's « Détails » pushes the detail screen; playback starts from there.
struct HomeScreen: View {
    let model: HomeModel
    let onPlay: (PlayTarget) -> Void
    @State private var path: [HomeRoute] = []

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
                onOpenDetail: { path.append(.detail($0)) },
                onSeeAll: { path.append(.grid($0)) },
                onToggleList: { Task { await model.toggleBillboardList() } }
            )
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .grid(let library):
                    RecentGridScreen(model: model, library: library, onOpen: { path.append(.detail($0)) })
                case .detail(let id):
                    DetailScreen(model: model.detailModel(for: id), onPlay: onPlay)
                }
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
