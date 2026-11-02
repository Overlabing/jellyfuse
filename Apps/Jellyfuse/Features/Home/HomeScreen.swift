import HomePresentation
import LibraryKit
import SwiftUI

/// Where this tab's stack can go. Both destinations stay on the tab's own stack: Menu pops them.
enum HomeRoute: Hashable {
    case grid(Library)
    case detail(String)
    case person(id: String, name: String)
}

/// Composition layer: wires `HomeModel` to the pure `HomeView`. « Voir tout » pushes the library grid,
/// a poster or the billboard's « Détails » pushes the detail screen; playback starts from there.
struct HomeScreen: View {
    let model: HomeModel
    let isPlayerOpen: Bool
    let onPlay: (PlayTarget) -> Void
    @State private var path: [HomeRoute] = []
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    private var isPolling: Bool {
        HomeRefreshPolicy.shouldPoll(sceneIsActive: scenePhase == .active, homeIsVisible: isVisible, playerIsOpen: isPlayerOpen)
    }

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
                    DetailScreen(
                        model: model.detailModel(for: id), onPlay: onPlay,
                        onOpenPerson: { path.append(.person(id: $0, name: $1)) }
                    )
                case .person(let id, let name):
                    FixedGridScreen(
                        title: name, key: GridKey(.person(id: id), sort: LibrarySort(.year)),
                        model: model.gridModel(), onOpen: { path.append(.detail($0)) }
                    )
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task { await model.refresh() }
        // Settled on the home: revalidate periodically. Stale-only, so a tick on fresh data sends nothing.
        .task(id: isPolling) {
            while isPolling {
                try? await Task.sleep(for: HomeRefreshPolicy.pollInterval)
                if Task.isCancelled { return }
                await model.refresh()
            }
        }
    }

    private static func message(for failure: UserFacingError) -> String {
        switch failure {
        case .network: String(localized: "Serveur injoignable.")
        case .unauthorized: String(localized: "Session expirée.")
        case .server, .unreadable, .other: String(localized: "Impossible de charger l'accueil.")
        }
    }
}
