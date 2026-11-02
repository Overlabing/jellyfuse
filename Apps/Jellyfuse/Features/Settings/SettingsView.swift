import DesignSystem
import SettingsKit
import SwiftUI

/// Réglages as a native grouped list. Pure: data in, callbacks out.
struct SettingsView: View {
    let account: AccountSummary?
    let version: String
    let onSignOut: () -> Void
    let onResetTrackChoices: () -> Void
    let onOpenLicenses: () -> Void

    @State private var confirmingSignOut = false
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section("Compte") {
                LabeledContent("Serveur", value: account?.serverAddress ?? "—")
                LabeledContent("Utilisateur", value: account?.userName ?? "—")
                Button("Se déconnecter", role: .destructive) { confirmingSignOut = true }
            }
            Section("Lecture") {
                Button("Réinitialiser les choix de pistes") { confirmingReset = true }
            }
            Section("À propos") {
                LabeledContent("Version", value: version)
                Button("Licences", action: onOpenLicenses)
            }
        }
        .confirmationDialog("Se déconnecter ?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive, action: onSignOut)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vous devrez vous reconnecter pour retrouver votre bibliothèque.")
        }
        .confirmationDialog("Réinitialiser les choix de pistes ?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Réinitialiser", role: .destructive, action: onResetTrackChoices)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les langues audio et sous-titres mémorisées pour chaque film et série seront oubliées.")
        }
    }
}
