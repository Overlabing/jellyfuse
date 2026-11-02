import LibraryKit
import PlaybackEngine
import SettingsKit
import SwiftUI

/// Composition layer of the Réglages tab: its own navigation stack, session actions, the bundled license catalog.
struct SettingsScreen: View {
    let session: Session?
    let playback: PlaybackServices?
    let onSignOut: () -> Void

    private enum Route: Hashable {
        case licenses
        case license(String)
    }

    @State private var path = NavigationPath()
    private let catalog = try? LicenseCatalog.bundled()

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(
                account: session.map(AccountSummary.init),
                version: AppVersion.display(Bundle.main.infoDictionary),
                onSignOut: onSignOut,
                onResetTrackChoices: { playback?.trackPreferences.removeAll() },
                onOpenLicenses: { path.append(Route.licenses) }
            )
            .navigationTitle("Réglages")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .licenses:
                    LicensesView(catalog: catalog, onOpen: { path.append(Route.license($0.id)) })
                        .navigationTitle("Licences")
                case .license(let id):
                    if let entry = catalog?.manifest.entries.first(where: { $0.id == id }) {
                        LicenseDetailView(entry: entry, text: catalog?.text(for: entry))
                    }
                }
            }
        }
    }
}
