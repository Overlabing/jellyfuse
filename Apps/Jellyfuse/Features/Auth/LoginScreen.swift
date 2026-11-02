import DesignSystem
import LibraryKit
import SwiftUI

/// Composition layer for sign-in: owns the model, picks the step view.
struct LoginScreen: View {
    @State private var model: LoginModel

    init(onSignedIn: @escaping @MainActor (Session) -> Void) {
        _model = State(initialValue: LoginModel(onSignedIn: onSignedIn))
    }

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .topLeading) {
            Design.Palette.canvas.ignoresSafeArea()
            Wordmark().padding(.top, Design.Spacing.m)
            switch model.step {
            case .server:
                ServerStepView(
                    address: $model.serverText, isBusy: model.isBusy, errorMessage: model.errorMessage,
                    onContinue: { Task { await model.connect() } }
                )
            case .quickConnect:
                QuickConnectStepView(
                    code: model.code, link: model.quickConnectLink, host: model.serverHost,
                    onUsePassword: model.usePassword, onChangeServer: model.changeServer
                )
            case .password:
                PasswordStepView(
                    userName: $model.userName, password: $model.password, isBusy: model.isBusy,
                    errorMessage: model.errorMessage, host: model.serverHost,
                    onSubmit: { Task { await model.submitPassword() } }, onChangeServer: model.changeServer
                )
            }
        }
        .padding(.horizontal, Design.Metrics.tv.screenMargin)
        .padding(.vertical, Design.Metrics.tv.safeVertical)
    }
}

// MARK: - Steps (pure views)

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            Text(title).font(Design.Typography.title).foregroundStyle(Design.Palette.textPrimary)
            Text(subtitle)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.textSecondary)
                .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct ErrorLine: View {
    let message: String?

    var body: some View {
        Text(message ?? "")
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.warning)
            .opacity(message == nil ? 0 : 1)
            .accessibilityHidden(message == nil)
    }
}

private struct ServerStepView: View {
    @Binding var address: String
    let isBusy: Bool
    let errorMessage: String?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.l) {
            StepHeader(
                title: String(localized: "Serveur"),
                subtitle: String(localized: "Saisissez l'adresse de votre serveur Jellyfin.")
            )
            TextField(String(localized: "jellyfin.local:8096"), text: $address)
                .onSubmit(onContinue)
                .frame(maxWidth: 900)
            ErrorLine(message: errorMessage)
            PillButton(isBusy ? String(localized: "Connexion…") : String(localized: "Continuer"), systemImage: "arrow.right", action: onContinue)
                .disabled(isBusy)
        }
        .padding(.top, 170)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct QuickConnectStepView: View {
    let code: String?
    let link: URL?
    let host: String?
    let onUsePassword: () -> Void
    let onChangeServer: () -> Void
    @Namespace private var focusNamespace

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                StepHeader(
                    title: String(localized: "Connexion rapide"),
                    subtitle: String(localized: "Sur un autre appareil déjà connecté à Jellyfin, ouvrez Profil › Connexion rapide et saisissez ce code.")
                )
                CodeDigits(code: code)
                Text(code == nil ? String(localized: "Génération du code…") : String(localized: "En attente d'autorisation…"))
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textSecondary)
            }
            .padding(.top, 170)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let link {
                VStack(spacing: Design.Spacing.s) {
                    QRCodeView(url: link, side: 300)
                    Text("Ou scannez ce code avec votre téléphone")
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 300)
                }
                .padding(.top, 190)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            HStack(spacing: Design.Spacing.m) {
                PillButton(String(localized: "Utiliser un mot de passe"), systemImage: "key.fill", action: onUsePassword)
                    .prefersDefaultFocus(in: focusNamespace)
                PillButton(String(localized: "Changer de serveur"), systemImage: "server.rack", action: onChangeServer)
                if let host {
                    Text(host).font(Design.Typography.caption).foregroundStyle(Design.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .focusScope(focusNamespace)
    }
}

/// Six boxed digits, split 3 + 3 like the mockup.
private struct CodeDigits: View {
    let code: String?

    var body: some View {
        let digits = Array((code ?? "").prefix(6))
        HStack(spacing: Design.Spacing.s) {
            ForEach(0..<6, id: \.self) { index in
                if index == 3 { Spacer().frame(width: Design.Spacing.s) }
                Text(index < digits.count ? String(digits[index]) : "")
                    .font(.system(size: 92, weight: .bold)) // ui-plan §3.2 code size; no DesignSystem token yet
                    .monospacedDigit()
                    .foregroundStyle(Design.Palette.textPrimary)
                    .frame(width: 112, height: 150)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Design.Spacing.m))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code.map { String(localized: "Code \($0)") } ?? String(localized: "Code en cours de génération"))
    }
}

private struct PasswordStepView: View {
    @Binding var userName: String
    @Binding var password: String
    let isBusy: Bool
    let errorMessage: String?
    let host: String?
    let onSubmit: () -> Void
    let onChangeServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.l) {
            StepHeader(
                title: String(localized: "Connexion"),
                subtitle: host.map { String(localized: "Serveur : \($0)") } ?? ""
            )
            TextField(String(localized: "Nom d'utilisateur"), text: $userName)
                .frame(maxWidth: 900)
            SecureField(String(localized: "Mot de passe"), text: $password)
                .onSubmit(onSubmit)
                .frame(maxWidth: 900)
            ErrorLine(message: errorMessage)
            HStack(spacing: Design.Spacing.m) {
                PillButton(isBusy ? String(localized: "Connexion…") : String(localized: "Se connecter"), systemImage: "arrow.right", action: onSubmit)
                    .disabled(isBusy)
                PillButton(String(localized: "Changer de serveur"), systemImage: "server.rack", action: onChangeServer)
            }
        }
        .padding(.top, 170)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
