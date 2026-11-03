import DesignSystem
import SettingsKit
import SwiftUI

/// The Licences list. A row opens the full text; a component without a sourced text points at its repository.
struct LicensesView: View {
    let catalog: LicenseCatalog?
    let onOpen: (LicenseEntry) -> Void

    var body: some View {
        if let catalog {
            List {
                Section {
                    Text("Jellyfuse est un logiciel libre sous licence MIT. Il lit les vidéos avec libmpv et FFmpeg, utilisés sous licence LGPL. Le code source, de quoi recompiler l'app avec une autre version de ces bibliothèques, est sur github.com/Overlabing/jellyfuse.")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Palette.textSecondary)
                }
                ForEach(LicenseEntry.Group.allCases, id: \.self) { group in
                    Section(Self.title(group)) {
                        ForEach(catalog.manifest.entries(in: group)) { entry in
                            Button { onOpen(entry) } label: {
                                LabeledContent {
                                    Text(entry.license ?? String(localized: "Voir le dépôt"))
                                } label: {
                                    Text(entry.name)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("Les licences sont introuvables dans cette version de l'app.")
                .foregroundStyle(Design.Palette.textSecondary)
        }
    }

    private static func title(_ group: LicenseEntry.Group) -> LocalizedStringKey {
        switch group {
        case .app: "Application"
        case .playback: "Lecture vidéo"
        case .sdk: "Jellyfin et bibliothèques Swift"
        }
    }
}

/// One component: facts, then the verbatim text in a scrollable page (focusable so the remote can scroll it).
struct LicenseDetailView: View {
    @Environment(\.designMetrics) private var metrics
    let entry: LicenseEntry
    let text: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.m) {
                Text(entry.name).font(Design.Typography.title)
                Text(facts).foregroundStyle(Design.Palette.textSecondary)
                if let note = entry.note { Text(note).foregroundStyle(Design.Palette.textSecondary) }
                if let text {
                    Text(text).font(.system(.callout, design: .monospaced))
                } else {
                    Text("Le texte intégral n'est pas fourni avec l'app : voir le dépôt, \(entry.url).")
                }
            }
            .padding(metrics.isTouch ? Design.Spacing.s : Design.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(tvOS)
        .focusable()
        #endif
    }

    private var facts: String {
        [entry.version, entry.license, entry.url].compactMap { $0 }.joined(separator: " · ")
    }
}
